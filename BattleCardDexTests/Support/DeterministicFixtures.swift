import Foundation

nonisolated struct CreatureIndexFixture: Codable, Equatable, Sendable {
    nonisolated struct Creature: Codable, Equatable, Sendable {
        let id: Int
        let name: String
        let displayName: String
        let types: [String]
    }

    let schemaVersion: Int
    let creatures: [Creature]
}

nonisolated struct EvolutionFixture: Codable, Equatable, Sendable {
    nonisolated struct Chain: Codable, Equatable, Sendable {
        nonisolated struct Edge: Codable, Equatable, Sendable {
            let from: Int
            let to: Int
            let requirement: String
        }

        let id: String
        let rootID: Int
        let edges: [Edge]
    }

    let schemaVersion: Int
    let chains: [Chain]
}

nonisolated struct BattleCardFixture: Codable, Equatable, Sendable {
    nonisolated struct Card: Codable, Equatable, Sendable {
        let id: String
        let creatureID: Int
        let name: String
        let setName: String
        let number: String
        let rarity: String
    }

    let schemaVersion: Int
    let cards: [Card]
}

enum DeterministicFixtures {
    static func creatureIndex() throws -> CreatureIndexFixture {
        try decode("creature-index-1-6", as: CreatureIndexFixture.self)
    }

    static func evolutions() throws -> EvolutionFixture {
        try decode("evolution-cases", as: EvolutionFixture.self)
    }

    static func battleCards() throws -> BattleCardFixture {
        try decode("battle-cards", as: BattleCardFixture.self)
    }

    static func data(named name: String) throws -> Data {
        guard let url = Bundle(for: FixtureBundleToken.self).url(forResource: name, withExtension: "json") else {
            throw FixtureError.missingResource(name)
        }
        return try Data(contentsOf: url)
    }

    private static func decode<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data(named: name))
    }
}

private final class FixtureBundleToken {}

enum FixtureError: Error, Equatable {
    case missingResource(String)
}
