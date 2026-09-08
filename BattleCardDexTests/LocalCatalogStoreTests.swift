import Foundation
import SwiftData
import Testing
@testable import Battle_Card_Dex

@Suite(.serialized)
struct LocalCatalogStoreTests {
    @Test func inMemoryCRUDAndEveryQueryShape() async throws {
        let container = try LocalCatalogContainer.make(isStoredInMemoryOnly: true)
        let store = SwiftDataLocalCatalogStore(container: container)
        let documents = try [
            document(manifest(), id: "manifest-record", hash: "m1"),
            document(creature(id: 2, name: "river-runner", generation: "generation-2", types: ["water"]), id: "creature-2", hash: "c2"),
            document(creature(id: 1, name: "seed-creature", generation: "generation-1", types: ["leaf", "toxin"]), id: "creature-1", hash: "c1"),
            document(evolution(), id: "evolution-10", hash: "e1"),
            document(card(id: "set-a-007", related: [1], name: "Seed Creature", number: "007"), id: "card-set-a-007", hash: "b1"),
            document(card(id: "set-a-002", related: [2], name: "River Runner", number: "002"), id: "card-set-a-002", hash: "b2"),
        ]

        try await store.replace(documents)
        #expect(try await store.statistics() == .init(manifests: 1, creatures: 2, evolutionChains: 1, cards: 2))
        #expect(try await store.manifest(sourceID: "catalog-v1")?.revision == 3)
        #expect(try await store.creatures().map(\.id) == [1, 2])
        #expect(try await store.creatures(search: "2").map(\.id) == [2])
        #expect(try await store.creatures(search: "seed").map(\.id) == [1])
        #expect(try await store.creatures(generation: "generation-1").map(\.id) == [1])
        #expect(try await store.creatures(type: "toxin").map(\.id) == [1])
        #expect(try await store.evolution(containing: 2)?.id == 10)
        #expect(try await store.cards(relatedTo: 1).map(\.id) == ["set-a-007"])
        #expect(try await store.cards(relatedTo: 2, search: "002").map(\.id) == ["set-a-002"])
        #expect(try await store.fetch(.init(identifiers: ["creature-1", "card-set-a-007"])).value.map(\.identifier) == ["card-set-a-007", "creature-1"])

        try await store.removeAll()
        #expect(try await store.statistics() == .init(manifests: 0, creatures: 0, evolutionChains: 0, cards: 0))
    }

    @Test func upsertSkipsUnchangedAndLastDuplicateWins() async throws {
        let container = try LocalCatalogContainer.make(isStoredInMemoryOnly: true)
        let clock = LockedClock(Date(timeIntervalSince1970: 100))
        let store = SwiftDataLocalCatalogStore(container: container, now: { clock.value })
        let original = try document(creature(id: 1, name: "first-name"), id: "creature-1", hash: "same")
        try await store.replace([original])

        clock.value = Date(timeIntervalSince1970: 200)
        try await store.replace([original])
        let unchanged = try #require(ModelContext(container).fetch(FetchDescriptor<CachedCreature>()).first)
        #expect(unchanged.cachedAt == Date(timeIntervalSince1970: 100))

        let earlier = try document(creature(id: 1, name: "earlier"), id: "creature-old", hash: "earlier")
        let winner = try document(creature(id: 1, name: "predictable-winner"), id: "creature-new", hash: "winner")
        try await store.replace([earlier, winner])
        #expect(try await store.creatures().map(\.name) == ["predictable-winner"])
        let updated = try #require(ModelContext(container).fetch(FetchDescriptor<CachedCreature>()).first)
        #expect(updated.cachedAt == Date(timeIntervalSince1970: 200))
        #expect(updated.recordIdentifier == "creature-new")
    }

    @Test func invalidBatchRollsBackAndRetainsLastValidRows() async throws {
        let store = SwiftDataLocalCatalogStore(container: try LocalCatalogContainer.make(isStoredInMemoryOnly: true))
        let original = try document(creature(id: 1, name: "last-valid"), id: "creature-1", hash: "valid")
        try await store.replace([original])

        let proposed = try document(creature(id: 1, name: "must-not-commit"), id: "creature-1", hash: "changed")
        let invalid = try document(creature(id: 0, name: "invalid"), id: "creature-0", hash: "invalid")
        await #expect(throws: LocalCatalogStoreError.invalidSourceIdentifier("0")) {
            try await store.replace([proposed, invalid])
        }
        #expect(try await store.creatures().map(\.name) == ["last-valid"])
    }

    @Test func onDiskStorePersistsAndCanBeDeletedThenRecreatedEmpty() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "catalog.store")

        do {
            let store = SwiftDataLocalCatalogStore(container: try LocalCatalogContainer.make(url: url))
            try await store.replace([document(creature(id: 1, name: "disk-row"), id: "creature-1", hash: "disk")])
            #expect(try await store.statistics().creatures == 1)
        }
        do {
            let store = SwiftDataLocalCatalogStore(container: try LocalCatalogContainer.make(url: url))
            #expect(try await store.statistics().creatures == 1)
        }
        try LocalCatalogContainer.deleteStore(at: url)
        let recreated = SwiftDataLocalCatalogStore(container: try LocalCatalogContainer.make(url: url))
        #expect(try await recreated.statistics() == .init(manifests: 0, creatures: 0, evolutionChains: 0, cards: 0))
    }

    private func document<Value: NormalizedCatalogPayload>(_ payload: Value, id: String, hash: String) throws -> CatalogDocument {
        try CatalogDocument(identifier: id, envelope: CatalogPersistenceEnvelope(payload), contentHash: hash)
    }

    private func manifest() -> CatalogManifestPayload {
        .init(schemaVersion: 1, id: "catalog-v1", revision: 3, publishedAt: Date(timeIntervalSince1970: 50), creatureCount: 2, evolutionCount: 1, cardCount: 2, contentHashes: ["creature-1": "c1"])
    }

    private func creature(id: Int, name: String, generation: String? = "generation-1", types: [String] = ["leaf"]) -> CatalogCreaturePayload {
        .init(schemaVersion: 1, id: id, name: name, displayName: name, generation: generation, types: types, artworkURL: nil, genus: nil, description: nil, heightMetres: nil, weightKilograms: nil, baseExperience: nil, abilities: [], hiddenAbilities: [], stats: .init(hitPoints: 1, attack: 1, defense: 1, specialAttack: 1, specialDefense: 1, speed: 1), forms: [], moves: [], encounters: [], versionGroups: [])
    }

    private func evolution() -> CatalogEvolutionPayload {
        let child = CatalogEvolutionNode(creatureID: 2, name: "river-runner", requirements: [], children: [])
        return .init(schemaVersion: 1, id: 10, root: .init(creatureID: 1, name: "seed-creature", requirements: [], children: [child]))
    }

    private func card(id: String, related: [Int], name: String, number: String) -> CatalogCardPayload {
        .init(schemaVersion: 1, id: id, relatedCreatureIDs: related, name: name, setID: "set-a", setName: "Set A", collectorNumber: number, rarity: nil, types: [], hitPoints: nil, smallImageURL: nil, largeImageURL: nil, subtypes: [], rules: [], abilities: [], attacks: [], weaknesses: [], resistances: [], retreatCost: [], evolutionText: nil, artist: nil, flavorText: nil, regulationMark: nil, legalities: [:])
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date
    init(_ value: Date) { stored = value }
    var value: Date {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
