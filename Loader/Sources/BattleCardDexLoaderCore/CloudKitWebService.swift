import CryptoKit
import Foundation

public struct CloudKitWebServiceConfiguration: Equatable, Sendable {
    public let containerIdentifier: String
    public let environment: String
    public let database: String
    public let baseURL: URL

    public init(containerIdentifier: String, environment: String = "development", database: String = "public",
                baseURL: URL = URL(string: "https://api.apple-cloudkit.com")!) throws {
        guard containerIdentifier.hasPrefix("iCloud."), environment == "development", database == "public" else {
            throw CloudKitWebServiceError.unsafeConfiguration
        }
        self.containerIdentifier = containerIdentifier
        self.environment = environment
        self.database = database
        self.baseURL = baseURL
    }

    func URLFor(_ operation: String) -> URL {
        baseURL.appendingPathComponent("database/1/\(containerIdentifier)/\(environment)/\(database)/\(operation)")
    }
}

public enum CloudKitWebServiceError: Error, Equatable, Sendable {
    case unsafeConfiguration
    case invalidPrivateKey
    case invalidResponse
    case httpStatus(Int)
    case server(code: String, recordName: String?, reason: String?)
}

/// A deliberately small, typed view of fields returned by CloudKit Web
/// Services. Validation only asks CloudKit for fields that are part of the
/// catalog contract; unsupported field shapes are retained as `.unknown` and
/// therefore cannot be mistaken for a valid catalog value.
public enum CloudKitQueriedField: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case data(Data)
    case strings([String])
    case integers([Int64])
    case unknown
}

public struct CloudKitQueriedRecord: Equatable, Sendable {
    public let recordName: String
    public let recordType: String
    public let fields: [String: CloudKitQueriedField]

    public init(recordName: String, recordType: String, fields: [String: CloudKitQueriedField]) {
        self.recordName = recordName
        self.recordType = recordType
        self.fields = fields
    }
}

public struct CloudKitQueryResult: Equatable, Sendable {
    public let records: [CloudKitQueriedRecord]
    /// Bytes in CloudKit's JSON response bodies for this query, across every
    /// continuation page. This is an observed validation-transfer measurement,
    /// not an estimate of CloudKit's internal index storage.
    public let responseBytes: Int

    public init(records: [CloudKitQueriedRecord], responseBytes: Int) {
        self.records = records
        self.responseBytes = responseBytes
    }
}

public protocol LoaderCloudKitQuerying: Sendable {
    func queryRecords(recordType: String, desiredKeys: [String]) async throws -> CloudKitQueryResult
}

public protocol CloudKitRequestSigning: Sendable {
    func signedHeaders(body: Data, url: URL) throws -> [String: String]
}

/// Implements Apple's server-to-server signature format. The private key is read
/// for each process invocation and is never copied into reports or checkpoints.
public struct CloudKitRequestSigner: CloudKitRequestSigning {
    private let keyID: String
    private let privateKeyURL: URL
    private let now: @Sendable () -> Date

    public init(credentials: CloudKitServerCredentials, now: @escaping @Sendable () -> Date = Date.init) {
        keyID = credentials.keyID
        privateKeyURL = credentials.privateKeyPath
        self.now = now
    }

    public func signedHeaders(body: Data, url: URL) throws -> [String: String] {
        let pem = try String(contentsOf: privateKeyURL, encoding: .utf8)
        let key: P256.Signing.PrivateKey
        do { key = try P256.Signing.PrivateKey(pemRepresentation: pem) }
        catch { throw CloudKitWebServiceError.invalidPrivateKey }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.string(from: now())
        let bodyHash = Data(SHA256.hash(data: body)).base64EncodedString()
        let subpath = url.path + (url.query.map { "?\($0)" } ?? "")
        let message = Data("\(date):\(bodyHash):\(subpath)".utf8)
        let signature = try key.signature(for: message).derRepresentation.base64EncodedString()
        return [
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": keyID,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        ]
    }
}

public actor CloudKitWebService: LoaderCloudKitService, LoaderCloudKitQuerying {
    private let configuration: CloudKitWebServiceConfiguration
    private let transport: any LoaderTransport
    private let signer: any CloudKitRequestSigning

    public init(configuration: CloudKitWebServiceConfiguration, transport: any LoaderTransport = URLSessionLoaderTransport(),
                signer: any CloudKitRequestSigning) {
        self.configuration = configuration
        self.transport = transport
        self.signer = signer
    }

    public func existingHashes(for identifiers: [String]) async throws -> [String: String] {
        guard !identifiers.isEmpty else { return [:] }
        var hashes: [String: String] = [:]
        let sortedIdentifiers = identifiers.sorted()
        for start in stride(from: 0, to: sortedIdentifiers.count, by: 100) {
            let end = min(start + 100, sortedIdentifiers.count)
            let body = try JSONSerialization.data(withJSONObject: [
                "records": sortedIdentifiers[start..<end].map { ["recordName": $0] },
                "desiredKeys": ["contentHash"],
            ], options: [.sortedKeys])
            let response = try await send(operation: "records/lookup", body: body)
            let records = try responseRecords(response.body)
            for record in records {
                guard record["serverErrorCode"] == nil,
                      let name = record["recordName"] as? String,
                      let fields = record["fields"] as? [String: Any],
                      let hashField = fields["contentHash"] as? [String: Any],
                      let hash = hashField["value"] as? String else { continue }
                hashes[name] = hash
            }
        }
        return hashes
    }

    public func save(_ records: [LoaderRecord]) async throws {
        guard !records.isEmpty else { return }
        let operations: [[String: Any]] = try records.map { record in
            guard !record.recordType.isEmpty else { throw CloudKitPublisherError.emptyRecordIdentifier }
            var fields = record.fields.mapValues(Self.webField)
            fields["contentHash"] = ["value": record.contentHash]
            fields["payload"] = ["value": record.payload.base64EncodedString(), "type": "BYTES"]
            return [
                "operationType": "forceReplace",
                "record": ["recordName": record.identifier, "recordType": record.recordType, "fields": fields],
            ]
        }
        let body = try JSONSerialization.data(withJSONObject: ["operations": operations], options: [.sortedKeys])
        let response = try await send(operation: "records/modify", body: body)
        let results = try responseRecords(response.body)
        let failureResults = results.filter { $0["serverErrorCode"] != nil }
        if let failure = failureResults.first,
           let code = failure["serverErrorCode"] as? String {
            throw CloudKitWebServiceError.server(code: code, recordName: failure["recordName"] as? String,
                                                 reason: failure["reason"] as? String)
        }
    }

    /// Reads every page for one Development/public record type. This method has
    /// no mutation path; `CloudKitWebServiceConfiguration` rejects production
    /// and non-public database construction before any request can be made.
    public func queryRecords(recordType: String, desiredKeys: [String]) async throws -> CloudKitQueryResult {
        let allowedTypes: Set<String> = ["CatalogManifest", "CreatureCatalogRecord", "EvolutionCatalogRecord", "CardCatalogRecord"]
        guard allowedTypes.contains(recordType) else { throw CloudKitWebServiceError.unsafeConfiguration }

        var continuationMarker: String?
        var seenMarkers = Set<String>()
        var records: [CloudKitQueriedRecord] = []
        var responseBytes = 0
        repeat {
            var body: [String: Any] = [
                "query": ["recordType": recordType, "filterBy": []],
                "desiredKeys": desiredKeys.sorted(),
                "resultsLimit": 200,
            ]
            if let continuationMarker { body["continuationMarker"] = continuationMarker }
            let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            let response = try await send(operation: "records/query", body: data)
            responseBytes += response.body.count
            let root = try responseRoot(response.body)
            records.append(contentsOf: try responseRecords(root).map(Self.queriedRecord))
            continuationMarker = root["continuationMarker"] as? String
            if let continuationMarker, !seenMarkers.insert(continuationMarker).inserted {
                throw CloudKitWebServiceError.invalidResponse
            }
        } while continuationMarker != nil
        return CloudKitQueryResult(records: records, responseBytes: responseBytes)
    }

    private func send(operation: String, body: Data) async throws -> LoaderHTTPResponse {
        let url = configuration.URLFor(operation)
        let headers = try signer.signedHeaders(body: body, url: url)
        let response = try await transport.send(LoaderHTTPRequest(url: url, method: .post, headers: headers, body: body))
        guard (200..<300).contains(response.statusCode) else { throw CloudKitWebServiceError.httpStatus(response.statusCode) }
        return response
    }

    private func responseRoot(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudKitWebServiceError.invalidResponse
        }
        if let code = root["serverErrorCode"] as? String {
            throw CloudKitWebServiceError.server(code: code, recordName: root["recordName"] as? String,
                                                 reason: root["reason"] as? String)
        }
        return root
    }

    private func responseRecords(_ data: Data) throws -> [[String: Any]] {
        try responseRecords(responseRoot(data))
    }

    private func responseRecords(_ root: [String: Any]) throws -> [[String: Any]] {
        guard let records = root["records"] as? [[String: Any]] else { throw CloudKitWebServiceError.invalidResponse }
        return records
    }

    private static func queriedRecord(_ source: [String: Any]) throws -> CloudKitQueriedRecord {
        guard let recordName = source["recordName"] as? String,
              let recordType = source["recordType"] as? String else {
            throw CloudKitWebServiceError.invalidResponse
        }
        let sourceFields = source["fields"] as? [String: Any] ?? [:]
        return CloudKitQueriedRecord(recordName: recordName, recordType: recordType,
                                     fields: sourceFields.mapValues(queriedField))
    }

    private static func queriedField(_ source: Any) -> CloudKitQueriedField {
        guard let field = source as? [String: Any], let value = field["value"] else { return .unknown }
        switch field["type"] as? String {
        case "BYTES":
            guard let encoded = value as? String, let data = Data(base64Encoded: encoded) else { return .unknown }
            return .data(data)
        case "INT64":
            guard let value = value as? NSNumber else { return .unknown }
            return .integer(value.int64Value)
        case "INT64_LIST":
            guard let values = value as? [NSNumber] else { return .unknown }
            return .integers(values.map(\.int64Value))
        default:
            if let value = value as? String { return .string(value) }
            if let values = value as? [String] { return .strings(values) }
            return .unknown
        }
    }

    private static func webField(_ field: LoaderRecordField) -> [String: Any] {
        switch field {
        case let .string(value): ["value": value]
        case let .integer(value): ["value": value, "type": "INT64"]
        case let .date(value): ["value": Int64(value.timeIntervalSince1970 * 1_000), "type": "TIMESTAMP"]
        case let .data(value): ["value": value.base64EncodedString(), "type": "BYTES"]
        case let .strings(value): ["value": value]
        case let .integers(value): ["value": value, "type": "INT64_LIST"]
        }
    }
}
