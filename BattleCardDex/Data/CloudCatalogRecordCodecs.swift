import CloudKit
import CryptoKit
import Foundation

nonisolated enum CloudCatalogRecordContract {
    static let supportedSchemaVersion = 1
    static let maximumPayloadBytes = 900 * 1_024

    enum RecordType {
        static let manifest = "CatalogManifest"
        static let creature = "CreatureCatalogRecord"
        static let evolution = "EvolutionCatalogRecord"
        static let card = "CardCatalogRecord"
    }

    enum Field {
        static let schemaVersion = "schemaVersion"
        static let sourceIdentifier = "sourceIdentifier"
        static let contentHash = "contentHash"
        static let loaderTimestamp = "loaderTimestamp"
        static let sourceTimestamp = "sourceTimestamp"
        static let payload = "payload"
        static let revision = "revision"
        static let publishedAt = "publishedAt"
        static let creatureCount = "creatureCount"
        static let evolutionCount = "evolutionCount"
        static let cardCount = "cardCount"
        static let normalizedName = "normalizedName"
        static let displayName = "displayName"
        static let generation = "generation"
        static let types = "types"
        static let memberIdentifiers = "memberIdentifiers"
        static let setIdentifier = "setIdentifier"
        static let collectorNumber = "collectorNumber"
        static let relatedCreatureIdentifiers = "relatedCreatureIdentifiers"
    }
}

/// A value-only CloudKit boundary used by codecs and deterministic unit fakes.
/// `CKRecord` conversion is deliberately separate from normalized/domain storage.
nonisolated enum CloudCatalogFieldValue: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case date(Date)
    case data(Data)
    case strings([String])
    case integers([Int64])
}

nonisolated protocol CloudCatalogRecordReading: Sendable {
    var recordType: String { get }
    var recordName: String { get }
    func value(for field: String) -> CloudCatalogFieldValue?
}

nonisolated struct CloudCatalogRecordSnapshot: CloudCatalogRecordReading, Equatable, Sendable {
    let recordType: String
    let recordName: String
    let fields: [String: CloudCatalogFieldValue]

    func value(for field: String) -> CloudCatalogFieldValue? { fields[field] }

    init(recordType: String, recordName: String, fields: [String: CloudCatalogFieldValue]) {
        self.recordType = recordType
        self.recordName = recordName
        self.fields = fields
    }

    init(record: CKRecord) throws {
        var decoded: [String: CloudCatalogFieldValue] = [:]
        for key in record.allKeys() {
            switch record[key] {
            case let value as String: decoded[key] = .string(value)
            case let value as NSNumber: decoded[key] = .integer(value.int64Value)
            case let value as Date: decoded[key] = .date(value)
            case let value as Data: decoded[key] = .data(value)
            case let value as [String]: decoded[key] = .strings(value)
            case let value as [NSNumber]: decoded[key] = .integers(value.map(\.int64Value))
            default: throw CloudCatalogRecordError.unsupportedCloudKitValue(key)
            }
        }
        self.init(recordType: record.recordType, recordName: record.recordID.recordName, fields: decoded)
    }

    func makeCKRecord() -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName))
        for (key, value) in fields {
            switch value {
            case .string(let value): record[key] = value as CKRecordValue
            case .integer(let value): record[key] = NSNumber(value: value)
            case .date(let value): record[key] = value as CKRecordValue
            case .data(let value): record[key] = value as CKRecordValue
            case .strings(let value): record[key] = value as CKRecordValue
            case .integers(let value): record[key] = value.map(NSNumber.init(value:)) as CKRecordValue
            }
        }
        return record
    }
}

nonisolated enum CloudCatalogRecordError: Error, Equatable, Sendable {
    case wrongRecordType(expected: String, actual: String)
    case wrongRecordName(expected: String, actual: String)
    case missingField(String)
    case wrongFieldType(String)
    case unsupportedSchemaVersion(Int)
    case invalidIdentifier(String)
    case invalidTimestamp(String)
    case invalidContentHash
    case payloadTooLarge(actual: Int, maximum: Int)
    case payloadKindMismatch
    case malformedPayload
    case unsupportedCloudKitValue(String)
}

nonisolated struct DecodedCloudCatalogRecord<Value: NormalizedCatalogPayload>: Equatable, Sendable {
    let value: Value
    let contentHash: String
    let loaderTimestamp: Date
    let sourceTimestamp: Date?
}

nonisolated struct CatalogManifestRecordCodec {
    static func encode(
        _ value: CatalogManifestPayload,
        loaderTimestamp: Date,
        sourceTimestamp: Date? = nil
    ) throws -> CloudCatalogRecordSnapshot {
        try CloudCatalogRecordCoder.encode(
            value,
            recordType: CloudCatalogRecordContract.RecordType.manifest,
            recordName: "catalog-manifest-v\(value.schemaVersion)",
            sourceIdentifier: .string(value.id),
            loaderTimestamp: loaderTimestamp,
            sourceTimestamp: sourceTimestamp ?? value.publishedAt,
            projectedFields: [
                CloudCatalogRecordContract.Field.revision: .integer(Int64(value.revision)),
                CloudCatalogRecordContract.Field.publishedAt: .date(value.publishedAt),
                CloudCatalogRecordContract.Field.creatureCount: .integer(Int64(value.creatureCount)),
                CloudCatalogRecordContract.Field.evolutionCount: .integer(Int64(value.evolutionCount)),
                CloudCatalogRecordContract.Field.cardCount: .integer(Int64(value.cardCount)),
            ]
        )
    }

    static func decode(_ record: some CloudCatalogRecordReading) throws -> DecodedCloudCatalogRecord<CatalogManifestPayload> {
        let decoded = try CloudCatalogRecordCoder.decode(
            record, as: CatalogManifestPayload.self,
            expectedRecordType: CloudCatalogRecordContract.RecordType.manifest,
            expectedRecordName: { "catalog-manifest-v\($0.schemaVersion)" }
        )
        guard case .string(let identifier) = record.value(for: CloudCatalogRecordContract.Field.sourceIdentifier) else {
            throw CloudCatalogRecordCoder.missingOrWrong(record, CloudCatalogRecordContract.Field.sourceIdentifier)
        }
        guard identifier == decoded.value.id else { throw CloudCatalogRecordError.invalidIdentifier(identifier) }
        try CloudCatalogRecordCoder.requireIntegerProjections(record, [
            (CloudCatalogRecordContract.Field.revision, decoded.value.revision),
            (CloudCatalogRecordContract.Field.creatureCount, decoded.value.creatureCount),
            (CloudCatalogRecordContract.Field.evolutionCount, decoded.value.evolutionCount),
            (CloudCatalogRecordContract.Field.cardCount, decoded.value.cardCount),
        ])
        guard case .date(let publishedAt)? = record.value(for: CloudCatalogRecordContract.Field.publishedAt) else {
            throw CloudCatalogRecordError.wrongFieldType(CloudCatalogRecordContract.Field.publishedAt)
        }
        // CloudKit Web Services persists TIMESTAMP projections at millisecond
        // precision. The normalized JSON payload can retain finer Date
        // precision, so exact equality rejects an otherwise valid manifest.
        guard abs(publishedAt.timeIntervalSince(decoded.value.publishedAt)) < 0.001 else {
            throw CloudCatalogRecordError.wrongFieldType(CloudCatalogRecordContract.Field.publishedAt)
        }
        return decoded
    }
}

nonisolated struct CreatureCatalogRecordCodec {
    static func encode(_ value: CatalogCreaturePayload, loaderTimestamp: Date, sourceTimestamp: Date? = nil) throws -> CloudCatalogRecordSnapshot {
        guard value.id > 0 else { throw CloudCatalogRecordError.invalidIdentifier(String(value.id)) }
        var projections: [String: CloudCatalogFieldValue] = [
            CloudCatalogRecordContract.Field.normalizedName: .string(value.name),
            CloudCatalogRecordContract.Field.displayName: .string(value.displayName),
            CloudCatalogRecordContract.Field.types: .strings(value.types),
        ]
        if let generation = value.generation { projections[CloudCatalogRecordContract.Field.generation] = .string(generation) }
        return try CloudCatalogRecordCoder.encode(
            value, recordType: CloudCatalogRecordContract.RecordType.creature,
            recordName: "catalog-creature-\(value.id)", sourceIdentifier: .integer(Int64(value.id)),
            loaderTimestamp: loaderTimestamp, sourceTimestamp: sourceTimestamp, projectedFields: projections
        )
    }

    static func decode(_ record: some CloudCatalogRecordReading) throws -> DecodedCloudCatalogRecord<CatalogCreaturePayload> {
        let decoded = try CloudCatalogRecordCoder.decode(
            record, as: CatalogCreaturePayload.self,
            expectedRecordType: CloudCatalogRecordContract.RecordType.creature,
            expectedRecordName: { "catalog-creature-\($0.id)" }
        )
        try CloudCatalogRecordCoder.requirePositiveIntegerIdentifier(record, equals: decoded.value.id)
        try CloudCatalogRecordCoder.requireString(record, CloudCatalogRecordContract.Field.normalizedName, equals: decoded.value.name)
        try CloudCatalogRecordCoder.requireString(record, CloudCatalogRecordContract.Field.displayName, equals: decoded.value.displayName)
        try CloudCatalogRecordCoder.requireStrings(record, CloudCatalogRecordContract.Field.types, equals: decoded.value.types)
        try CloudCatalogRecordCoder.requireOptionalString(record, CloudCatalogRecordContract.Field.generation, equals: decoded.value.generation)
        return decoded
    }
}

nonisolated struct EvolutionCatalogRecordCodec {
    static func encode(_ value: CatalogEvolutionPayload, loaderTimestamp: Date, sourceTimestamp: Date? = nil) throws -> CloudCatalogRecordSnapshot {
        guard value.id > 0 else { throw CloudCatalogRecordError.invalidIdentifier(String(value.id)) }
        let members = CloudCatalogRecordCoder.evolutionMemberIdentifiers(value.root).map(Int64.init)
        return try CloudCatalogRecordCoder.encode(
            value, recordType: CloudCatalogRecordContract.RecordType.evolution,
            recordName: "catalog-evolution-\(value.id)", sourceIdentifier: .integer(Int64(value.id)),
            loaderTimestamp: loaderTimestamp, sourceTimestamp: sourceTimestamp,
            projectedFields: [CloudCatalogRecordContract.Field.memberIdentifiers: .integers(members)]
        )
    }

    static func decode(_ record: some CloudCatalogRecordReading) throws -> DecodedCloudCatalogRecord<CatalogEvolutionPayload> {
        let decoded = try CloudCatalogRecordCoder.decode(
            record, as: CatalogEvolutionPayload.self,
            expectedRecordType: CloudCatalogRecordContract.RecordType.evolution,
            expectedRecordName: { "catalog-evolution-\($0.id)" }
        )
        try CloudCatalogRecordCoder.requirePositiveIntegerIdentifier(record, equals: decoded.value.id)
        let members = CloudCatalogRecordCoder.evolutionMemberIdentifiers(decoded.value.root).map(Int64.init)
        guard record.value(for: CloudCatalogRecordContract.Field.memberIdentifiers) == .integers(members) else {
            throw CloudCatalogRecordError.wrongFieldType(CloudCatalogRecordContract.Field.memberIdentifiers)
        }
        return decoded
    }
}

nonisolated struct CardCatalogRecordCodec {
    static func encode(_ value: CatalogCardPayload, loaderTimestamp: Date, sourceTimestamp: Date? = nil) throws -> CloudCatalogRecordSnapshot {
        try CloudCatalogRecordCoder.validateTextIdentifier(value.id)
        guard value.relatedCreatureIDs.allSatisfy({ $0 > 0 }) else {
            throw CloudCatalogRecordError.invalidIdentifier(value.relatedCreatureIDs.map(String.init).joined(separator: ","))
        }
        return try CloudCatalogRecordCoder.encode(
            value, recordType: CloudCatalogRecordContract.RecordType.card,
            recordName: "catalog-card-\(CloudCatalogRecordCoder.hash(Data(value.id.utf8)))",
            sourceIdentifier: .string(value.id), loaderTimestamp: loaderTimestamp, sourceTimestamp: sourceTimestamp,
            projectedFields: [
                CloudCatalogRecordContract.Field.normalizedName: .string(value.name.lowercased()),
                CloudCatalogRecordContract.Field.displayName: .string(value.name),
                CloudCatalogRecordContract.Field.setIdentifier: .string(value.setID),
                CloudCatalogRecordContract.Field.collectorNumber: .string(value.collectorNumber),
                CloudCatalogRecordContract.Field.types: .strings(value.types),
                CloudCatalogRecordContract.Field.relatedCreatureIdentifiers: .integers(value.relatedCreatureIDs.map(Int64.init)),
            ]
        )
    }

    static func decode(_ record: some CloudCatalogRecordReading) throws -> DecodedCloudCatalogRecord<CatalogCardPayload> {
        let decoded = try CloudCatalogRecordCoder.decode(
            record, as: CatalogCardPayload.self,
            expectedRecordType: CloudCatalogRecordContract.RecordType.card,
            expectedRecordName: { "catalog-card-\(CloudCatalogRecordCoder.hash(Data($0.id.utf8)))" }
        )
        guard case .string(let identifier) = record.value(for: CloudCatalogRecordContract.Field.sourceIdentifier) else {
            throw CloudCatalogRecordCoder.missingOrWrong(record, CloudCatalogRecordContract.Field.sourceIdentifier)
        }
        try CloudCatalogRecordCoder.validateTextIdentifier(identifier)
        guard identifier == decoded.value.id else { throw CloudCatalogRecordError.invalidIdentifier(identifier) }
        try CloudCatalogRecordCoder.requireString(record, CloudCatalogRecordContract.Field.normalizedName, equals: decoded.value.name.lowercased())
        try CloudCatalogRecordCoder.requireString(record, CloudCatalogRecordContract.Field.displayName, equals: decoded.value.name)
        try CloudCatalogRecordCoder.requireString(record, CloudCatalogRecordContract.Field.setIdentifier, equals: decoded.value.setID)
        try CloudCatalogRecordCoder.requireString(record, CloudCatalogRecordContract.Field.collectorNumber, equals: decoded.value.collectorNumber)
        try CloudCatalogRecordCoder.requireStrings(record, CloudCatalogRecordContract.Field.types, equals: decoded.value.types)
        guard record.value(for: CloudCatalogRecordContract.Field.relatedCreatureIdentifiers) == .integers(decoded.value.relatedCreatureIDs.map(Int64.init)) else {
            throw CloudCatalogRecordError.wrongFieldType(CloudCatalogRecordContract.Field.relatedCreatureIdentifiers)
        }
        return decoded
    }
}

private nonisolated enum CloudCatalogRecordCoder {
    static func encode<Value: NormalizedCatalogPayload>(
        _ value: Value,
        recordType: String,
        recordName: String,
        sourceIdentifier: CloudCatalogFieldValue,
        loaderTimestamp: Date,
        sourceTimestamp: Date?,
        projectedFields: [String: CloudCatalogFieldValue]
    ) throws -> CloudCatalogRecordSnapshot {
        guard value.schemaVersion == CloudCatalogRecordContract.supportedSchemaVersion else {
            throw CloudCatalogRecordError.unsupportedSchemaVersion(value.schemaVersion)
        }
        guard loaderTimestamp.timeIntervalSince1970 >= 0 else { throw CloudCatalogRecordError.invalidTimestamp(CloudCatalogRecordContract.Field.loaderTimestamp) }
        if let sourceTimestamp, sourceTimestamp.timeIntervalSince1970 < 0 {
            throw CloudCatalogRecordError.invalidTimestamp(CloudCatalogRecordContract.Field.sourceTimestamp)
        }
        let envelope: CatalogPersistenceEnvelope
        do { envelope = try CatalogPersistenceEnvelope(value) }
        catch CatalogEnvelopeError.unsupportedSchema(let version) { throw CloudCatalogRecordError.unsupportedSchemaVersion(version) }
        catch { throw CloudCatalogRecordError.malformedPayload }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(envelope)
        try validateSize(payload)
        var fields = projectedFields
        fields[CloudCatalogRecordContract.Field.schemaVersion] = .integer(Int64(value.schemaVersion))
        fields[CloudCatalogRecordContract.Field.sourceIdentifier] = sourceIdentifier
        fields[CloudCatalogRecordContract.Field.contentHash] = .string(hash(payload))
        fields[CloudCatalogRecordContract.Field.loaderTimestamp] = .date(loaderTimestamp)
        fields[CloudCatalogRecordContract.Field.payload] = .data(payload)
        if let sourceTimestamp { fields[CloudCatalogRecordContract.Field.sourceTimestamp] = .date(sourceTimestamp) }
        return .init(recordType: recordType, recordName: recordName, fields: fields)
    }

    static func decode<Value: NormalizedCatalogPayload>(
        _ record: some CloudCatalogRecordReading,
        as type: Value.Type,
        expectedRecordType: String,
        expectedRecordName: (Value) -> String
    ) throws -> DecodedCloudCatalogRecord<Value> {
        guard record.recordType == expectedRecordType else {
            throw CloudCatalogRecordError.wrongRecordType(expected: expectedRecordType, actual: record.recordType)
        }
        let schema = try integer(record, CloudCatalogRecordContract.Field.schemaVersion)
        guard schema == CloudCatalogRecordContract.supportedSchemaVersion else {
            throw CloudCatalogRecordError.unsupportedSchemaVersion(schema)
        }
        guard case .data(let payload)? = record.value(for: CloudCatalogRecordContract.Field.payload) else {
            throw missingOrWrong(record, CloudCatalogRecordContract.Field.payload)
        }
        try validateSize(payload)
        guard case .string(let claimedHash)? = record.value(for: CloudCatalogRecordContract.Field.contentHash) else {
            throw missingOrWrong(record, CloudCatalogRecordContract.Field.contentHash)
        }
        guard claimedHash == hash(payload) else { throw CloudCatalogRecordError.invalidContentHash }
        guard case .date(let loaderTimestamp)? = record.value(for: CloudCatalogRecordContract.Field.loaderTimestamp) else {
            throw missingOrWrong(record, CloudCatalogRecordContract.Field.loaderTimestamp)
        }
        guard loaderTimestamp.timeIntervalSince1970 >= 0 else { throw CloudCatalogRecordError.invalidTimestamp(CloudCatalogRecordContract.Field.loaderTimestamp) }
        let sourceTimestamp: Date?
        if let value = record.value(for: CloudCatalogRecordContract.Field.sourceTimestamp) {
            guard case .date(let date) = value else { throw CloudCatalogRecordError.wrongFieldType(CloudCatalogRecordContract.Field.sourceTimestamp) }
            guard date.timeIntervalSince1970 >= 0 else { throw CloudCatalogRecordError.invalidTimestamp(CloudCatalogRecordContract.Field.sourceTimestamp) }
            sourceTimestamp = date
        } else { sourceTimestamp = nil }
        let envelope: CatalogPersistenceEnvelope
        do { envelope = try CatalogPersistenceEnvelope.validatingPersistedBytes(payload) }
        catch CatalogEnvelopeError.unsupportedSchema(let version) { throw CloudCatalogRecordError.unsupportedSchemaVersion(version) }
        catch { throw CloudCatalogRecordError.malformedPayload }
        guard envelope.schemaVersion == schema, envelope.kind == Value.kind else { throw CloudCatalogRecordError.payloadKindMismatch }
        let value: Value
        do { value = try envelope.decode(Value.self) }
        catch { throw CloudCatalogRecordError.malformedPayload }
        let expectedName = expectedRecordName(value)
        guard record.recordName == expectedName else {
            throw CloudCatalogRecordError.wrongRecordName(expected: expectedName, actual: record.recordName)
        }
        return .init(value: value, contentHash: claimedHash, loaderTimestamp: loaderTimestamp, sourceTimestamp: sourceTimestamp)
    }

    static func missingOrWrong(_ record: some CloudCatalogRecordReading, _ field: String) -> CloudCatalogRecordError {
        record.value(for: field) == nil ? .missingField(field) : .wrongFieldType(field)
    }

    static func integer(_ record: some CloudCatalogRecordReading, _ field: String) throws -> Int {
        guard case .integer(let value)? = record.value(for: field) else { throw missingOrWrong(record, field) }
        guard let exact = Int(exactly: value) else { throw CloudCatalogRecordError.wrongFieldType(field) }
        return exact
    }

    static func requirePositiveIntegerIdentifier(_ record: some CloudCatalogRecordReading, equals expected: Int) throws {
        let value = try integer(record, CloudCatalogRecordContract.Field.sourceIdentifier)
        guard value > 0, value == expected else { throw CloudCatalogRecordError.invalidIdentifier(String(value)) }
    }

    static func requireIntegerProjections(_ record: some CloudCatalogRecordReading, _ fields: [(String, Int)]) throws {
        for (field, expected) in fields where try integer(record, field) != expected {
            throw CloudCatalogRecordError.wrongFieldType(field)
        }
    }

    static func requireString(_ record: some CloudCatalogRecordReading, _ field: String, equals expected: String) throws {
        guard case .string(let value)? = record.value(for: field) else { throw missingOrWrong(record, field) }
        guard value == expected else { throw CloudCatalogRecordError.wrongFieldType(field) }
    }

    static func requireOptionalString(_ record: some CloudCatalogRecordReading, _ field: String, equals expected: String?) throws {
        switch (record.value(for: field), expected) {
        case (nil, nil): return
        case (.string(let value)?, .some(let expected)) where value == expected: return
        case (nil, .some): throw CloudCatalogRecordError.missingField(field)
        default: throw CloudCatalogRecordError.wrongFieldType(field)
        }
    }

    static func requireStrings(_ record: some CloudCatalogRecordReading, _ field: String, equals expected: [String]) throws {
        guard record.value(for: field) == .strings(expected) else { throw missingOrWrong(record, field) }
    }

    static func validateTextIdentifier(_ identifier: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !identifier.isEmpty, identifier.utf8.count <= 255,
              identifier.unicodeScalars.allSatisfy(allowed.contains) else {
            throw CloudCatalogRecordError.invalidIdentifier(identifier)
        }
    }

    static func validateSize(_ payload: Data) throws {
        guard payload.count <= CloudCatalogRecordContract.maximumPayloadBytes else {
            throw CloudCatalogRecordError.payloadTooLarge(actual: payload.count, maximum: CloudCatalogRecordContract.maximumPayloadBytes)
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func evolutionMemberIdentifiers(_ root: CatalogEvolutionNode) -> [Int] {
        var members: [Int] = []
        func visit(_ node: CatalogEvolutionNode) {
            members.append(node.creatureID)
            node.children.forEach(visit)
        }
        visit(root)
        return Array(Set(members)).sorted()
    }
}
