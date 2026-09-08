import CloudKit
import Foundation
import Testing
@testable import Battle_Card_Dex

@Suite("Public CloudKit record codecs")
struct CloudCatalogRecordCodecTests {
    private let loaderTime = Date(timeIntervalSince1970: 2_000)
    private let sourceTime = Date(timeIntervalSince1970: 1_000)

    @Test func everyRecordTypeRoundTripsThroughFakeRecords() throws {
        let manifest = manifestPayload()
        let creature = creaturePayload()
        let evolution = evolutionPayload()
        let card = cardPayload()

        let manifestRecord = try CatalogManifestRecordCodec.encode(manifest, loaderTimestamp: loaderTime)
        let creatureRecord = try CreatureCatalogRecordCodec.encode(creature, loaderTimestamp: loaderTime, sourceTimestamp: sourceTime)
        let evolutionRecord = try EvolutionCatalogRecordCodec.encode(evolution, loaderTimestamp: loaderTime)
        let cardRecord = try CardCatalogRecordCodec.encode(card, loaderTimestamp: loaderTime, sourceTimestamp: sourceTime)

        #expect(try CatalogManifestRecordCodec.decode(FakeRecord(manifestRecord)).value == manifest)
        #expect(try CreatureCatalogRecordCodec.decode(FakeRecord(creatureRecord)).value == creature)
        #expect(try EvolutionCatalogRecordCodec.decode(FakeRecord(evolutionRecord)).value == evolution)
        #expect(try CardCatalogRecordCodec.decode(FakeRecord(cardRecord)).value == card)
        #expect(try CatalogManifestRecordCodec.decode(FakeRecord(manifestRecord)).sourceTimestamp == manifest.publishedAt)
        #expect(try CreatureCatalogRecordCodec.decode(FakeRecord(creatureRecord)).loaderTimestamp == loaderTime)
        #expect(try CreatureCatalogRecordCodec.decode(FakeRecord(creatureRecord)).sourceTimestamp == sourceTime)
    }

    @Test func snapshotsRoundTripThroughConcreteCKRecordsWithoutAssets() throws {
        let snapshots = try [
            CatalogManifestRecordCodec.encode(manifestPayload(), loaderTimestamp: loaderTime),
            CreatureCatalogRecordCodec.encode(creaturePayload(), loaderTimestamp: loaderTime),
            EvolutionCatalogRecordCodec.encode(evolutionPayload(), loaderTimestamp: loaderTime),
            CardCatalogRecordCodec.encode(cardPayload(), loaderTimestamp: loaderTime),
        ]

        for snapshot in snapshots {
            let record = snapshot.makeCKRecord()
            #expect(!record.allKeys().contains { record[$0] is CKAsset })
            #expect(try CloudCatalogRecordSnapshot(record: record) == snapshot)
        }
        #expect(try CardCatalogRecordCodec.decode(CloudCatalogRecordSnapshot(record: snapshots[3].makeCKRecord())).value == cardPayload())
    }

    @Test func manifestAcceptsCloudKitMillisecondTimestampPrecision() throws {
        let preciseDate = Date(timeIntervalSince1970: 2_000.123_456)
        let manifest = manifestPayload(publishedAt: preciseDate)
        let encoded = try CatalogManifestRecordCodec.encode(manifest, loaderTimestamp: loaderTime)
        var fields = encoded.fields
        fields[CloudCatalogRecordContract.Field.publishedAt] = .date(
            Date(timeIntervalSince1970: 2_000.123)
        )
        let cloudKitRecord = FakeRecord(
            recordType: encoded.recordType,
            recordName: encoded.recordName,
            fields: fields
        )

        #expect(try CatalogManifestRecordCodec.decode(cloudKitRecord).value == manifest)
    }

    @Test func missingRequiredFieldsAndWrongTypesAreRejected() throws {
        let valid = try CreatureCatalogRecordCodec.encode(creaturePayload(), loaderTimestamp: loaderTime)
        var missing = valid.fields
        missing.removeValue(forKey: CloudCatalogRecordContract.Field.payload)
        #expect(throws: CloudCatalogRecordError.missingField(CloudCatalogRecordContract.Field.payload)) {
            try CreatureCatalogRecordCodec.decode(FakeRecord(recordType: valid.recordType, recordName: valid.recordName, fields: missing))
        }

        var wrongType = valid.fields
        wrongType[CloudCatalogRecordContract.Field.schemaVersion] = .string("1")
        #expect(throws: CloudCatalogRecordError.wrongFieldType(CloudCatalogRecordContract.Field.schemaVersion)) {
            try CreatureCatalogRecordCodec.decode(FakeRecord(recordType: valid.recordType, recordName: valid.recordName, fields: wrongType))
        }
    }

    @Test func unsupportedSchemaAndOversizedPayloadAreRejected() throws {
        var fields = try CreatureCatalogRecordCodec.encode(creaturePayload(), loaderTimestamp: loaderTime).fields
        fields[CloudCatalogRecordContract.Field.schemaVersion] = .integer(2)
        #expect(throws: CloudCatalogRecordError.unsupportedSchemaVersion(2)) {
            try CreatureCatalogRecordCodec.decode(FakeRecord(
                recordType: CloudCatalogRecordContract.RecordType.creature,
                recordName: "catalog-creature-25",
                fields: fields
            ))
        }

        let oversized = CatalogCreaturePayload(
            schemaVersion: 1, id: 25, name: "spark-mouse", displayName: "Spark Mouse",
            generation: nil, types: ["electric"], artworkURL: nil, genus: nil,
            description: String(repeating: "a", count: CloudCatalogRecordContract.maximumPayloadBytes + 1),
            heightMetres: nil, weightKilograms: nil, baseExperience: nil,
            abilities: [], hiddenAbilities: [], stats: stats(), forms: [], moves: [], encounters: [], versionGroups: []
        )
        #expect(throws: CloudCatalogRecordError.self) {
            try CreatureCatalogRecordCodec.encode(oversized, loaderTimestamp: loaderTime)
        }
    }

    @Test func invalidSourceIdentifiersAndMismatchedRecordNamesAreRejected() throws {
        #expect(throws: CloudCatalogRecordError.invalidIdentifier("0")) {
            try CreatureCatalogRecordCodec.encode(creaturePayload(id: 0), loaderTimestamp: loaderTime)
        }
        #expect(throws: CloudCatalogRecordError.invalidIdentifier("unsafe/id")) {
            try CardCatalogRecordCodec.encode(cardPayload(id: "unsafe/id"), loaderTimestamp: loaderTime)
        }

        let valid = try EvolutionCatalogRecordCodec.encode(evolutionPayload(), loaderTimestamp: loaderTime)
        #expect(throws: CloudCatalogRecordError.wrongRecordName(expected: "catalog-evolution-7", actual: "catalog-evolution-8")) {
            try EvolutionCatalogRecordCodec.decode(FakeRecord(recordType: valid.recordType, recordName: "catalog-evolution-8", fields: valid.fields))
        }
    }

    @Test func recordNamesHashesAndVocabularyAreDeterministicAndNeutral() throws {
        let first = try CardCatalogRecordCodec.encode(cardPayload(), loaderTimestamp: loaderTime, sourceTimestamp: sourceTime)
        let second = try CardCatalogRecordCodec.encode(cardPayload(), loaderTimestamp: loaderTime, sourceTimestamp: sourceTime)
        #expect(first.recordName == second.recordName)
        #expect(first.fields[CloudCatalogRecordContract.Field.contentHash] == second.fields[CloudCatalogRecordContract.Field.contentHash])

        let records = try [
            CatalogManifestRecordCodec.encode(manifestPayload(), loaderTimestamp: loaderTime),
            CreatureCatalogRecordCodec.encode(creaturePayload(), loaderTimestamp: loaderTime),
            EvolutionCatalogRecordCodec.encode(evolutionPayload(), loaderTimestamp: loaderTime),
            first,
        ]
        let allowedRecordTypes = Set(["CatalogManifest", "CreatureCatalogRecord", "EvolutionCatalogRecord", "CardCatalogRecord"])
        let allowedFields = Set([
            "schemaVersion", "sourceIdentifier", "contentHash", "loaderTimestamp", "sourceTimestamp", "payload",
            "revision", "publishedAt", "creatureCount", "evolutionCount", "cardCount", "normalizedName",
            "displayName", "generation", "types", "memberIdentifiers", "setIdentifier", "collectorNumber",
            "relatedCreatureIdentifiers",
        ])
        #expect(records.allSatisfy { allowedRecordTypes.contains($0.recordType) })
        #expect(records.allSatisfy { Set($0.fields.keys).isSubset(of: allowedFields) })
        #expect(records.allSatisfy { $0.recordName.hasPrefix("catalog-") })
    }

    private func manifestPayload(publishedAt: Date? = nil) -> CatalogManifestPayload {
        .init(schemaVersion: 1, id: "catalog-v1", revision: 4, publishedAt: publishedAt ?? sourceTime,
              creatureCount: 1, evolutionCount: 1, cardCount: 1, contentHashes: ["creature-25": "abc"])
    }

    private func creaturePayload(id: Int = 25) -> CatalogCreaturePayload {
        .init(schemaVersion: 1, id: id, name: "spark-mouse", displayName: "Spark Mouse",
              generation: "generation-1", types: ["electric"],
              artworkURL: URL(string: "https://images.example.invalid/creature/25.png"),
              genus: "Mouse", description: "Stores electrical energy.", heightMetres: 0.4,
              weightKilograms: 6, baseExperience: 112, abilities: ["static-charge"], hiddenAbilities: [],
              stats: stats(), forms: [], moves: [], encounters: [], versionGroups: ["first"])
    }

    private func stats() -> CatalogStats {
        .init(hitPoints: 35, attack: 55, defense: 40, specialAttack: 50, specialDefense: 50, speed: 90)
    }

    private func evolutionPayload() -> CatalogEvolutionPayload {
        let child = CatalogEvolutionNode(creatureID: 26, name: "storm-mouse", requirements: [], children: [])
        return .init(schemaVersion: 1, id: 7, root: .init(creatureID: 25, name: "spark-mouse", requirements: [], children: [child]))
    }

    private func cardPayload(id: String = "set-a-001") -> CatalogCardPayload {
        .init(schemaVersion: 1, id: id, relatedCreatureIDs: [25], name: "Spark Mouse",
              setID: "set-a", setName: "First Set", collectorNumber: "001", rarity: "rare",
              types: ["electric"], hitPoints: 60,
              smallImageURL: URL(string: "https://images.example.invalid/cards/small.png"),
              largeImageURL: URL(string: "https://images.example.invalid/cards/large.png"),
              subtypes: ["basic"], rules: [], abilities: [], attacks: ["Spark"], weaknesses: [],
              resistances: [], retreatCost: ["neutral"], evolutionText: nil, artist: nil,
              flavorText: "A bright companion.", regulationMark: "A", legalities: ["standard": "Legal"])
    }
}

private struct FakeRecord: CloudCatalogRecordReading {
    let recordType: String
    let recordName: String
    let fields: [String: CloudCatalogFieldValue]

    init(_ snapshot: CloudCatalogRecordSnapshot) {
        recordType = snapshot.recordType
        recordName = snapshot.recordName
        fields = snapshot.fields
    }

    init(recordType: String, recordName: String, fields: [String: CloudCatalogFieldValue]) {
        self.recordType = recordType
        self.recordName = recordName
        self.fields = fields
    }

    func value(for field: String) -> CloudCatalogFieldValue? { fields[field] }
}
