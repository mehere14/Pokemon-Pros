import Foundation
import Testing

@testable import Battle_Card_Dex

@Test("batch normalization sorts records and hashes semantic payloads")
func batchNormalizationIsDeterministic() throws {
    let creatures = (1...6).map { id in
        CatalogCreaturePayload(schemaVersion: 1, id: id, name: "creature-\(id)", displayName: "Creature \(id)", generation: nil, types: [], artworkURL: nil, genus: nil, description: nil, heightMetres: nil, weightKilograms: nil, baseExperience: nil, abilities: [], hiddenAbilities: [], stats: CatalogStats(hitPoints: 1, attack: 1, defense: 1, specialAttack: 1, specialDefense: 1, speed: 1), forms: [], moves: [], encounters: [], versionGroups: [])
    }
    let batchA = try CatalogBatchNormalizer.makeBatch(creatures: creatures.reversed(), evolutions: [], cards: [], supportedRange: 1...6)
    let batchB = try CatalogBatchNormalizer.makeBatch(creatures: creatures.shuffled(), evolutions: [], cards: [], supportedRange: 1...6)
    #expect(batchA == batchB)
    #expect(batchA.creatures.map(\.id) == [1, 2, 3, 4, 5, 6])
    #expect(batchA.contentHashes.count == 6)
}

@Test("evolution families can include out-of-range members")
func evolutionFamilyMayExtendRange() throws {
    let creatures = (1...2).map { id in
        CatalogCreaturePayload(schemaVersion: 1, id: id, name: "creature-\(id)", displayName: "Creature \(id)", generation: nil, types: [], artworkURL: nil, genus: nil, description: nil, heightMetres: nil, weightKilograms: nil, baseExperience: nil, abilities: [], hiddenAbilities: [], stats: CatalogStats(hitPoints: 1, attack: 1, defense: 1, specialAttack: 1, specialDefense: 1, speed: 1), forms: [], moves: [], encounters: [], versionGroups: [])
    }
    let evolution = CatalogEvolutionPayload(schemaVersion: 1, id: 1, root: CatalogEvolutionNode(creatureID: 1, name: "creature-1", requirements: [], children: [CatalogEvolutionNode(creatureID: 99, name: "creature-99", requirements: [], children: [])]))
    let batch = try CatalogBatchNormalizer.makeBatch(creatures: creatures, evolutions: [evolution], cards: [], supportedRange: 1...2)
    #expect(batch.evolutions.first?.root.children.first?.creatureID == 99)
}

@Test("unrelated cards and duplicate IDs block publication")
func invalidBatchRejected() throws {
    let creature = CatalogCreaturePayload(schemaVersion: 1, id: 1, name: "one", displayName: "One", generation: nil, types: [], artworkURL: nil, genus: nil, description: nil, heightMetres: nil, weightKilograms: nil, baseExperience: nil, abilities: [], hiddenAbilities: [], stats: CatalogStats(hitPoints: 1, attack: 1, defense: 1, specialAttack: 1, specialDefense: 1, speed: 1), forms: [], moves: [], encounters: [], versionGroups: [])
    let card = CatalogCardPayload(schemaVersion: 1, id: "card-1", relatedCreatureIDs: [2], name: "Card", setID: "set", setName: "Set", collectorNumber: "1", rarity: nil, types: [], hitPoints: nil, smallImageURL: nil, largeImageURL: nil, subtypes: [], rules: [], abilities: [], attacks: [], weaknesses: [], resistances: [], retreatCost: [], evolutionText: nil, artist: nil, flavorText: nil, regulationMark: nil, legalities: [:])
    #expect(throws: CatalogBatchValidationError.unrelatedCard("card-1")) {
        _ = try CatalogBatchNormalizer.makeBatch(creatures: [creature], evolutions: [], cards: [card], supportedRange: 1...1)
    }
    #expect(throws: CatalogBatchValidationError.duplicateCreatureID(1)) {
        _ = try CatalogBatchNormalizer.makeBatch(creatures: [creature, creature], evolutions: [], cards: [], supportedRange: 1...1)
    }
}
