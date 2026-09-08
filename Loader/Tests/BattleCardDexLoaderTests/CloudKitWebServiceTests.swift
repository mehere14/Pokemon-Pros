import Foundation
import CryptoKit
import Testing
@testable import BattleCardDexLoaderCore

private actor WebServiceTransport: LoaderTransport {
    private var responses: [LoaderHTTPResponse]
    private(set) var requests: [LoaderHTTPRequest] = []

    init(_ responses: [LoaderHTTPResponse]) { self.responses = responses }

    func send(_ request: LoaderHTTPRequest) async throws -> LoaderHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw CloudKitWebServiceError.invalidResponse }
        return responses.removeFirst()
    }
}

private struct DeterministicSigner: CloudKitRequestSigning {
    func signedHeaders(body: Data, url: URL) throws -> [String: String] {
        ["X-Test-Signature": "signed-\(body.count)"]
    }
}

private actor StaticCatalogQueryService: LoaderCloudKitQuerying {
    let results: [String: CloudKitQueryResult]

    init(_ results: [String: CloudKitQueryResult]) { self.results = results }

    func queryRecords(recordType: String, desiredKeys: [String]) async throws -> CloudKitQueryResult {
        guard let result = results[recordType] else { throw CloudKitWebServiceError.invalidResponse }
        return result
    }
}

private struct TestEnvelope: Encodable { let schemaVersion: Int; let kind: String; let payload: Data }
private struct TestManifest: Encodable {
    let schemaVersion: Int
    let id: String
    let revision: Int
    let publishedAt: Date
    let creatureCount: Int
    let evolutionCount: Int
    let cardCount: Int
    let contentHashes: [String: String]
}

private func testHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func dataRecord(_ name: String, _ type: String, fields: [String: CloudKitQueriedField], payload: Data) -> CloudKitQueriedRecord {
    var allFields = fields
    allFields["payload"] = .data(payload)
    allFields["contentHash"] = .string(testHash(payload))
    return CloudKitQueriedRecord(recordName: name, recordType: type, fields: allFields)
}

@Test("server signer emits a verifiable Apple request signature without exposing the key")
func cloudKitRequestSignature() throws {
    let privateKey = P256.Signing.PrivateKey()
    let keyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("p8")
    try Data(privateKey.pemRepresentation.utf8).write(to: keyURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: keyURL) }
    let credentials = CloudKitServerCredentials(keyID: "development-key", privateKeyPath: keyURL)
    let fixedDate = Date(timeIntervalSince1970: 1_788_586_543)
    let signer = CloudKitRequestSigner(credentials: credentials, now: { fixedDate })
    let body = Data(#"{"records":[]}"#.utf8)
    let url = URL(string: "https://api.apple-cloudkit.com/database/1/iCloud.com.example.catalog/development/public/records/lookup")!

    let headers = try signer.signedHeaders(body: body, url: url)
    let date = try #require(headers["X-Apple-CloudKit-Request-ISO8601Date"])
    let encodedSignature = try #require(headers["X-Apple-CloudKit-Request-SignatureV1"])
    let signatureData = try #require(Data(base64Encoded: encodedSignature))
    let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
    let hash = Data(SHA256.hash(data: body)).base64EncodedString()
    let signedMessage = Data("\(date):\(hash):\(url.path)".utf8)
    #expect(privateKey.publicKey.isValidSignature(signature, for: signedMessage))
    #expect(headers["X-Apple-CloudKit-Request-KeyID"] == "development-key")
    #expect(!headers.values.contains { $0.contains("PRIVATE KEY") })
}

@Test("CloudKit Web Services configuration rejects every Production write path")
func cloudKitConfigurationIsDevelopmentOnly() {
    #expect(throws: CloudKitWebServiceError.unsafeConfiguration) {
        _ = try CloudKitWebServiceConfiguration(containerIdentifier: "iCloud.com.example.catalog", environment: "production")
    }
    #expect(throws: CloudKitWebServiceError.unsafeConfiguration) {
        _ = try CloudKitWebServiceConfiguration(containerIdentifier: "not-a-container")
    }
}

@Test("CloudKit hash lookup uses signed Development public POST request")
func cloudKitHashLookup() async throws {
    let response = Data(#"{"records":[{"recordName":"catalog-creature-1","fields":{"contentHash":{"value":"abc"}}},{"recordName":"catalog-creature-2","serverErrorCode":"NOT_FOUND"}]}"#.utf8)
    let transport = WebServiceTransport([LoaderHTTPResponse(statusCode: 200, body: response)])
    let configuration = try CloudKitWebServiceConfiguration(containerIdentifier: "iCloud.com.example.catalog")
    let service = CloudKitWebService(configuration: configuration, transport: transport, signer: DeterministicSigner())

    let hashes = try await service.existingHashes(for: ["catalog-creature-2", "catalog-creature-1"])
    #expect(hashes == ["catalog-creature-1": "abc"])
    let request = try #require((await transport.requests).first)
    #expect(request.method == .post)
    #expect(request.url.path.hasSuffix("/development/public/records/lookup"))
    #expect(request.headers["X-Test-Signature"]?.hasPrefix("signed-") == true)
    let requestBody = try #require(request.body)
    let body = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let records = try #require(body["records"] as? [[String: String]])
    #expect(records.compactMap { $0["recordName"] } == ["catalog-creature-1", "catalog-creature-2"])
}

@Test("CloudKit save emits force-replace fields and surfaces partial failures")
func cloudKitSaveAndPartialFailure() async throws {
    let response = Data(#"{"records":[{"recordName":"catalog-creature-1"},{"recordName":"catalog-creature-2","serverErrorCode":"TRY_AGAIN_LATER"}]}"#.utf8)
    let transport = WebServiceTransport([LoaderHTTPResponse(statusCode: 200, body: response)])
    let configuration = try CloudKitWebServiceConfiguration(containerIdentifier: "iCloud.com.example.catalog")
    let service = CloudKitWebService(configuration: configuration, transport: transport, signer: DeterministicSigner())
    let records = [
        LoaderRecord(identifier: "catalog-creature-1", recordType: "CreatureCatalogRecord", contentHash: "a", payload: Data([1]), fields: ["schemaVersion": .integer(1)]),
        LoaderRecord(identifier: "catalog-creature-2", recordType: "CreatureCatalogRecord", contentHash: "b", payload: Data([2]), fields: ["schemaVersion": .integer(1)]),
    ]

    await #expect(throws: CloudKitWebServiceError.server(code: "TRY_AGAIN_LATER", recordName: "catalog-creature-2", reason: nil)) {
        try await service.save(records)
    }
    let request = try #require((await transport.requests).first)
    #expect(request.url.path.hasSuffix("/development/public/records/modify"))
    let requestBody = try #require(request.body)
    let body = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let operations = try #require(body["operations"] as? [[String: Any]])
    #expect(operations.count == 2)
    #expect(operations.allSatisfy { $0["operationType"] as? String == "forceReplace" })
}

@Test("CloudKit query follows continuation markers with a Development public read request")
func cloudKitQueryFollowsContinuations() async throws {
    let first = Data(#"{"records":[{"recordName":"catalog-creature-1","recordType":"CreatureCatalogRecord","fields":{"sourceIdentifier":{"value":1,"type":"INT64"}}}],"continuationMarker":"next-page"}"#.utf8)
    let second = Data(#"{"records":[{"recordName":"catalog-creature-2","recordType":"CreatureCatalogRecord","fields":{"sourceIdentifier":{"value":2,"type":"INT64"}}}]}"#.utf8)
    let transport = WebServiceTransport([LoaderHTTPResponse(statusCode: 200, body: first), LoaderHTTPResponse(statusCode: 200, body: second)])
    let configuration = try CloudKitWebServiceConfiguration(containerIdentifier: "iCloud.com.example.catalog")
    let service = CloudKitWebService(configuration: configuration, transport: transport, signer: DeterministicSigner())

    let result = try await service.queryRecords(recordType: "CreatureCatalogRecord", desiredKeys: ["sourceIdentifier"])
    #expect(result.records.map(\.recordName) == ["catalog-creature-1", "catalog-creature-2"])
    #expect(result.responseBytes == first.count + second.count)
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.url.path.hasSuffix("/development/public/records/query") })
    let secondBody = try #require(requests[1].body)
    let decoded = try #require(try JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
    #expect(decoded["continuationMarker"] as? String == "next-page")
}

@Test("Development validator independently verifies manifest counts and every first-range relationship")
func developmentCatalogValidation() async throws {
    let creaturePayload = Data("creature".utf8)
    let evolutionPayload = Data("evolution".utf8)
    let cardPayload = Data("card".utf8)
    let creature = dataRecord("catalog-creature-1", "CreatureCatalogRecord",
                              fields: ["sourceIdentifier": .integer(1)], payload: creaturePayload)
    let evolution = dataRecord("catalog-evolution-7", "EvolutionCatalogRecord",
                               fields: ["sourceIdentifier": .integer(7), "memberIdentifiers": .integers([1])], payload: evolutionPayload)
    let cardID = "sample-card"
    let card = dataRecord("catalog-card-\(testHash(Data(cardID.utf8)))", "CardCatalogRecord",
                          fields: ["sourceIdentifier": .string(cardID), "relatedCreatureIdentifiers": .integers([1])], payload: cardPayload)
    let hashes = [creature, evolution, card].reduce(into: [String: String]()) { result, record in
        if case let .string(hash)? = record.fields["contentHash"] { result[record.recordName] = hash }
    }
    let manifestValue = TestManifest(schemaVersion: 1, id: "catalog-manifest", revision: 1, publishedAt: .now,
                                     creatureCount: 1, evolutionCount: 1, cardCount: 1, contentHashes: hashes)
    let inner = try JSONEncoder().encode(manifestValue)
    let manifestPayload = try JSONEncoder().encode(TestEnvelope(schemaVersion: 1, kind: "manifest", payload: inner))
    let manifest = dataRecord("catalog-manifest-v1", "CatalogManifest", fields: [
        "sourceIdentifier": .string("catalog-manifest"),
        "creatureCount": .integer(1), "evolutionCount": .integer(1), "cardCount": .integer(1),
    ], payload: manifestPayload)
    let service = StaticCatalogQueryService([
        "CatalogManifest": .init(records: [manifest], responseBytes: 101),
        "CreatureCatalogRecord": .init(records: [creature], responseBytes: 102),
        "EvolutionCatalogRecord": .init(records: [evolution], responseBytes: 103),
        "CardCatalogRecord": .init(records: [card], responseBytes: 104),
    ])

    let range = try IndexRange(lowerBound: 1, upperBound: 1)
    let result = try await DevelopmentCatalogValidator(primaryRange: range).validate(service: service)
    #expect(result.recordCounts["catalogRecords"] == 4)
    #expect(result.recordCounts["uniquePrimarySourceIDs"] == 1)
    #expect(result.recordCounts["validatedEvolutionReferences"] == 1)
    #expect(result.recordCounts["validatedCardReferences"] == 1)
    #expect(result.recordCounts["validationResponseBytes"] == 410)
}
