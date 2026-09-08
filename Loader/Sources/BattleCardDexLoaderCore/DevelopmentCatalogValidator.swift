import CryptoKit
import Foundation

/// Validation failures are intentionally short, non-secret contract labels so
/// they can safely be emitted in the machine-readable loader report.
public enum CatalogValidationError: Error, Equatable, Sendable {
    case invalidCatalog(String)

    public var code: String {
        switch self {
        case let .invalidCatalog(reason): "catalog_validation_\(reason)"
        }
    }
}

public struct DevelopmentCatalogValidationResult: Equatable, Sendable {
    public let recordCounts: [String: Int]

    public init(recordCounts: [String: Int]) {
        self.recordCounts = recordCounts
    }
}

/// Read-only verification of the initial shared Development catalog. It uses
/// CloudKit queries rather than loader checkpoints or provider cache state, so
/// the counts and references are independently observed from the published
/// records themselves.
public struct DevelopmentCatalogValidator: Sendable {
    public let primaryRange: IndexRange

    public init(primaryRange: IndexRange = try! IndexRange(lowerBound: 1, upperBound: 30)) {
        self.primaryRange = primaryRange
    }

    public func validate(service: any LoaderCloudKitQuerying) async throws -> DevelopmentCatalogValidationResult {
        async let manifest = service.queryRecords(recordType: "CatalogManifest", desiredKeys: manifestKeys)
        async let creatures = service.queryRecords(recordType: "CreatureCatalogRecord", desiredKeys: commonKeys)
        async let evolutions = service.queryRecords(recordType: "EvolutionCatalogRecord", desiredKeys: evolutionKeys)
        async let cards = service.queryRecords(recordType: "CardCatalogRecord", desiredKeys: cardKeys)
        return try validate(manifest: await manifest, creatures: await creatures, evolutions: await evolutions, cards: await cards)
    }

    public func validate(manifest: CloudKitQueryResult, creatures: CloudKitQueryResult,
                         evolutions: CloudKitQueryResult, cards: CloudKitQueryResult) throws -> DevelopmentCatalogValidationResult {
        guard manifest.records.count == 1 else { throw invalid("manifest-count") }
        let manifestRecord = manifest.records[0]
        guard manifestRecord.recordName == "catalog-manifest-v1", manifestRecord.recordType == "CatalogManifest" else {
            throw invalid("manifest-identity")
        }

        let allDataRecords = creatures.records + evolutions.records + cards.records
        try verifyPayloadHashes(manifest.records + allDataRecords)
        let primaryIDs = try creatureIDs(creatures.records)
        let expectedPrimaryIDs = Set(primaryRange.lowerBound...primaryRange.upperBound)
        guard primaryIDs == expectedPrimaryIDs, creatures.records.count == primaryRange.count else { throw invalid("primary-creature-count") }

        let evolutionMembers = try evolutionMemberIDs(evolutions.records)
        guard expectedPrimaryIDs.isSubset(of: evolutionMembers) else { throw invalid("missing-evolution-reference") }

        let cardReferenceCounts = try cardReferences(cards.records, primaryIDs: expectedPrimaryIDs)
        guard expectedPrimaryIDs.allSatisfy({ (cardReferenceCounts[$0] ?? 0) > 0 }) else {
            throw invalid("missing-card-reference")
        }

        let storedManifest = try decodedManifest(manifestRecord)
        guard storedManifest.creatureCount == creatures.records.count,
              storedManifest.evolutionCount == evolutions.records.count,
              storedManifest.cardCount == cards.records.count else {
            throw invalid("manifest-payload-count")
        }
        try verifyManifestFields(manifestRecord, manifest: storedManifest)
        let remoteHashes = try Dictionary(uniqueKeysWithValues: allDataRecords.map { record in
            guard let hash = string(record, "contentHash") else { throw invalid("missing-content-hash") }
            return (record.recordName, hash)
        })
        // Compact manifests deliberately omit card hashes so their payload stays
        // below CloudKit's record-size ceiling as the catalog grows. Every hash
        // that is published must still match its corresponding remote record.
        guard storedManifest.contentHashes.allSatisfy({ remoteHashes[$0.key] == $0.value }) else {
            throw invalid("manifest-content-hashes")
        }
        let expectedManifestIDs = Set(creatures.records.map(\.recordName) + evolutions.records.map(\.recordName))
        guard expectedManifestIDs.isSubset(of: Set(storedManifest.contentHashes.keys)) else {
            throw invalid("manifest-content-hashes")
        }

        let payloadBytes = (manifest.records + allDataRecords).reduce(0) { partial, record in
            partial + (data(record, "payload")?.count ?? 0)
        }
        let responseBytes = manifest.responseBytes + creatures.responseBytes + evolutions.responseBytes + cards.responseBytes
        let cardReferenceTotal = cardReferenceCounts.values.reduce(0, +)
        return DevelopmentCatalogValidationResult(recordCounts: [
            "manifest": manifest.records.count,
            "creatures": creatures.records.count,
            "evolutions": evolutions.records.count,
            "cards": cards.records.count,
            "catalogRecords": manifest.records.count + allDataRecords.count,
            "uniquePrimarySourceIDs": primaryIDs.count,
            "validatedEvolutionReferences": expectedPrimaryIDs.count,
            "validatedCardReferences": cardReferenceTotal,
            "payloadBytes": payloadBytes,
            "validationResponseBytes": responseBytes,
        ])
    }

    private let commonKeys = ["sourceIdentifier", "contentHash", "payload"]
    private let manifestKeys = ["sourceIdentifier", "contentHash", "payload", "creatureCount", "evolutionCount", "cardCount"]
    private let evolutionKeys = ["sourceIdentifier", "memberIdentifiers", "contentHash", "payload"]
    private let cardKeys = ["sourceIdentifier", "relatedCreatureIdentifiers", "contentHash", "payload"]

    private func creatureIDs(_ records: [CloudKitQueriedRecord]) throws -> Set<Int> {
        var ids = Set<Int>()
        for record in records {
            guard record.recordType == "CreatureCatalogRecord",
                  let identifier = integer(record, "sourceIdentifier"), identifier > 0,
                  record.recordName == "catalog-creature-\(identifier)",
                  ids.insert(Int(identifier)).inserted else {
                throw invalid("duplicate-or-invalid-creature")
            }
        }
        return ids
    }

    private func evolutionMemberIDs(_ records: [CloudKitQueriedRecord]) throws -> Set<Int> {
        var sourceIDs = Set<Int>()
        var members = Set<Int>()
        for record in records {
            guard record.recordType == "EvolutionCatalogRecord",
                  let identifier = integer(record, "sourceIdentifier"), identifier > 0,
                  record.recordName == "catalog-evolution-\(identifier)",
                  sourceIDs.insert(Int(identifier)).inserted,
                  let listedMembers = integers(record, "memberIdentifiers"), !listedMembers.isEmpty else {
                throw invalid("invalid-evolution-record")
            }
            for member in listedMembers {
                guard member > 0 else { throw invalid("invalid-evolution-member") }
                members.insert(Int(member))
            }
        }
        return members
    }

    private func cardReferences(_ records: [CloudKitQueriedRecord], primaryIDs: Set<Int>) throws -> [Int: Int] {
        var sourceIDs = Set<String>()
        var counts: [Int: Int] = [:]
        for record in records {
            guard record.recordType == "CardCatalogRecord",
                  let identifier = string(record, "sourceIdentifier"), !identifier.isEmpty,
                  sourceIDs.insert(identifier).inserted,
                  record.recordName == "catalog-card-\(hash(Data(identifier.utf8)))",
                  let related = integers(record, "relatedCreatureIdentifiers"), !related.isEmpty else {
                throw invalid("invalid-card-record")
            }
            for relatedID in related {
                guard relatedID > 0 else { throw invalid("invalid-card-reference") }
                let id = Int(relatedID)
                if primaryIDs.contains(id) { counts[id, default: 0] += 1 }
            }
        }
        return counts
    }

    private func verifyPayloadHashes(_ records: [CloudKitQueriedRecord]) throws {
        for record in records {
            guard let payload = data(record, "payload"), !payload.isEmpty,
                  let storedHash = string(record, "contentHash"), storedHash == hash(payload) else {
                throw invalid("payload-hash")
            }
        }
    }

    private func decodedManifest(_ record: CloudKitQueriedRecord) throws -> StoredManifest {
        guard string(record, "sourceIdentifier") == "catalog-manifest",
              let payload = data(record, "payload") else { throw invalid("manifest-fields") }
        do {
            let envelope = try JSONDecoder().decode(StoredEnvelope.self, from: payload)
            guard envelope.schemaVersion == 1, envelope.kind == "manifest" else { throw invalid("manifest-envelope") }
            let manifest = try JSONDecoder().decode(StoredManifest.self, from: envelope.payload)
            guard manifest.schemaVersion == 1, manifest.id == "catalog-manifest", manifest.revision > 0 else {
                throw invalid("manifest-payload")
            }
            return manifest
        } catch let error as CatalogValidationError {
            throw error
        } catch {
            throw invalid("manifest-decode")
        }
    }

    private func verifyManifestFields(_ record: CloudKitQueriedRecord, manifest: StoredManifest) throws {
        guard integer(record, "creatureCount") == Int64(manifest.creatureCount),
              integer(record, "evolutionCount") == Int64(manifest.evolutionCount),
              integer(record, "cardCount") == Int64(manifest.cardCount) else {
            throw invalid("manifest-projected-count")
        }
    }

    private func string(_ record: CloudKitQueriedRecord, _ key: String) -> String? {
        guard case let .string(value)? = record.fields[key] else { return nil }
        return value
    }

    private func integer(_ record: CloudKitQueriedRecord, _ key: String) -> Int64? {
        guard case let .integer(value)? = record.fields[key] else { return nil }
        return value
    }

    private func integers(_ record: CloudKitQueriedRecord, _ key: String) -> [Int64]? {
        guard case let .integers(value)? = record.fields[key] else { return nil }
        return value
    }

    private func data(_ record: CloudKitQueriedRecord, _ key: String) -> Data? {
        guard case let .data(value)? = record.fields[key] else { return nil }
        return value
    }

    private func invalid(_ reason: String) -> CatalogValidationError { .invalidCatalog(reason) }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

private struct StoredEnvelope: Decodable {
    let schemaVersion: Int
    let kind: String
    let payload: Data
}

private struct StoredManifest: Decodable {
    let schemaVersion: Int
    let id: String
    let revision: Int
    let publishedAt: Date
    let creatureCount: Int
    let evolutionCount: Int
    let cardCount: Int
    let contentHashes: [String: String]
}
