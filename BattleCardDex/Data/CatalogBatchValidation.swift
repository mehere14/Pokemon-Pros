import CryptoKit
import Foundation

nonisolated enum CatalogBatchValidationError: Error, Equatable, Sendable {
    case emptyBatch
    case duplicateCreatureID(Int)
    case duplicateEvolutionID(Int)
    case duplicateCardID(String)
    case unsupportedRange(Int)
    case invalidEvolutionChain(Int)
    case danglingEvolutionReference(Int)
    case unrelatedCard(String)
    case missingImage(String)
    case oversizedPayload(String, Int)
    case unsafeText(String)
}

nonisolated struct NormalizedCatalogBatch: Equatable, Sendable {
    let creatures: [CatalogCreaturePayload]
    let evolutions: [CatalogEvolutionPayload]
    let cards: [CatalogCardPayload]
    let contentHashes: [String: String]

    var creatureIDs: Set<Int> { Set(creatures.map(\.id)) }
}

/// Joins normalized payloads at the loader/client boundary and applies all
/// referential and deterministic publication checks before a batch is written.
nonisolated enum CatalogBatchNormalizer {
    static func makeBatch(
        creatures: [CatalogCreaturePayload],
        evolutions: [CatalogEvolutionPayload],
        cards: [CatalogCardPayload],
        supportedRange: ClosedRange<Int>,
        requireImages: Bool = false
    ) throws -> NormalizedCatalogBatch {
        guard !creatures.isEmpty else { throw CatalogBatchValidationError.emptyBatch }
        try unique(creatures.map(\.id), duplicate: CatalogBatchValidationError.duplicateCreatureID)
        try unique(evolutions.map(\.id), duplicate: CatalogBatchValidationError.duplicateEvolutionID)
        try unique(cards.map(\.id), duplicate: CatalogBatchValidationError.duplicateCardID)
        guard creatures.allSatisfy({ supportedRange.contains($0.id) }) else {
            let bad = creatures.first(where: { !supportedRange.contains($0.id) })!.id
            throw CatalogBatchValidationError.unsupportedRange(bad)
        }

        let primaryIDs = Set(creatures.map(\.id))
        for evolution in evolutions {
            let members = memberIDs(in: evolution.root)
            guard !members.isEmpty, members.allSatisfy({ $0 > 0 }) else {
                throw CatalogBatchValidationError.invalidEvolutionChain(evolution.id)
            }
            // A chain may intentionally include family members outside the seed range;
            // it must still intersect at least one requested primary entry.
            guard !members.isDisjoint(with: primaryIDs) else {
                throw CatalogBatchValidationError.invalidEvolutionChain(evolution.id)
            }
        }
        for card in cards {
            guard !card.relatedCreatureIDs.isEmpty,
                  card.relatedCreatureIDs.allSatisfy({ $0 > 0 }),
                  !Set(card.relatedCreatureIDs).isDisjoint(with: primaryIDs) else {
                throw CatalogBatchValidationError.unrelatedCard(card.id)
            }
            if requireImages && (card.smallImageURL == nil || card.largeImageURL == nil) {
                throw CatalogBatchValidationError.missingImage(card.id)
            }
        }

        let sortedCreatures = creatures.sorted { $0.id < $1.id }
        let sortedEvolutions = evolutions.sorted { $0.id < $1.id }
        let sortedCards = cards.sorted { $0.id < $1.id }
        var hashes: [String: String] = [:]
        for value in sortedCreatures { hashes["creature:\(value.id)"] = try hash(value) }
        for value in sortedEvolutions { hashes["evolution:\(value.id)"] = try hash(value) }
        for value in sortedCards { hashes["card:\(value.id)"] = try hash(value) }
        return NormalizedCatalogBatch(creatures: sortedCreatures, evolutions: sortedEvolutions, cards: sortedCards, contentHashes: hashes)
    }

    static func manifest(for batch: NormalizedCatalogBatch, id: String = "catalog-manifest") -> CatalogManifestPayload {
        CatalogManifestPayload(schemaVersion: 1, id: id, revision: 1, publishedAt: Date(timeIntervalSince1970: 0),
                                creatureCount: batch.creatures.count, evolutionCount: batch.evolutions.count,
                                cardCount: batch.cards.count, contentHashes: batch.contentHashes)
    }

    private static func unique<Value: Hashable>(_ values: [Value], duplicate: (Value) -> CatalogBatchValidationError) throws {
        var seen = Set<Value>()
        for value in values where !seen.insert(value).inserted { throw duplicate(value) }
    }

    private static func memberIDs(in node: CatalogEvolutionNode) -> Set<Int> {
        [node.creatureID].reduce(into: Set<Int>()) { result, id in
            result.insert(id)
            for child in node.children { result.formUnion(memberIDs(in: child)) }
        }
    }

    private static func hash<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(value))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
