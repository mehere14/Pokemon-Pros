import Foundation

nonisolated struct CreatureSummary: Codable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
    let displayName: String
    let generation: String?
    let types: [String]
    let artworkURL: URL?
}

extension CreatureSummary: Identifiable {}

nonisolated struct CreatureForm: Codable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
    let displayName: String
    let isDefault: Bool
    let types: [String]
    let artworkURL: URL?
}

nonisolated struct CreatureStats: Codable, Equatable, Hashable, Sendable {
    let hitPoints: Int
    let attack: Int
    let defense: Int
    let specialAttack: Int
    let specialDefense: Int
    let speed: Int
}

nonisolated struct MoveSummary: Codable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
    let displayName: String
    let versionGroups: [String]
    let learningMethods: [String]
}

extension MoveSummary: Identifiable {}

nonisolated struct MoveDetail: Codable, Equatable, Hashable, Sendable {
    let summary: MoveSummary
    let type: String?
    let damageClass: String?
    let power: Int?
    let accuracy: Int?
    let powerPoints: Int?
    let priority: Int
    let effect: String?
}

nonisolated struct Encounter: Codable, Equatable, Hashable, Sendable {
    let location: String
    let versionGroups: [String]
    let minimumLevel: Int?
    let maximumLevel: Int?
    let chancePercent: Int?
}

nonisolated struct CreatureProfile: Codable, Equatable, Hashable, Sendable {
    let summary: CreatureSummary
    let genus: String?
    let description: String?
    let heightMetres: Double?
    let weightKilograms: Double?
    let baseExperience: Int?
    let captureRate: Int?
    let baseHappiness: Int?
    let growthRate: String?
    let abilities: [String]
    let hiddenAbilities: [String]
    let stats: CreatureStats
    let forms: [CreatureForm]
    let moves: [MoveSummary]
    let encounters: [Encounter]
    let versionGroups: [String]
}

nonisolated struct EvolutionRequirement: Codable, Equatable, Hashable, Sendable {
    let trigger: String?
    let minimumLevel: Int?
    let item: String?
    let heldItem: String?
    let tradeSpecies: String?
    let minimumHappiness: Int?
    let minimumAffection: Int?
    let minimumBeauty: Int?
    let timeOfDay: String?
    let location: String?
    let weather: String?
    let relativePhysicalStats: Int?
    let gender: String?
    let knownMove: String?
    let knownMoveType: String?
    let partySpecies: String?
    let partyType: String?
    let needsUpsideDownDevice: Bool
}

nonisolated struct EvolutionNode: Codable, Equatable, Hashable, Sendable {
    let creatureID: Int
    let name: String
    let requirements: [EvolutionRequirement]
    let children: [EvolutionNode]
}

nonisolated struct EvolutionChain: Codable, Equatable, Hashable, Sendable {
    let id: Int
    let root: EvolutionNode

    var memberIDs: [Int] {
        var result: [Int] = []
        func visit(_ node: EvolutionNode) {
            result.append(node.creatureID)
            node.children.forEach(visit)
        }
        visit(root)
        return Array(Set(result)).sorted()
    }
}

nonisolated struct BattleCardSummary: Codable, Equatable, Hashable, Sendable {
    let id: String
    let relatedCreatureIDs: [Int]
    let name: String
    let setID: String
    let setName: String
    let collectorNumber: String
    let rarity: String?
    let types: [String]
    let hitPoints: Int?
    let smallImageURL: URL?
    let largeImageURL: URL?
}

nonisolated struct BattleCardDetail: Codable, Equatable, Hashable, Sendable {
    let summary: BattleCardSummary
    let subtypes: [String]
    let rules: [String]
    let abilities: [String]
    let attacks: [String]
    let weaknesses: [String]
    let resistances: [String]
    let retreatCost: [String]
    let evolutionText: String?
    let artist: String?
    let flavorText: String?
    let regulationMark: String?
    let legalities: [String: String]
}

extension BattleCardDetail: Identifiable {
    var id: String { summary.id }
}
