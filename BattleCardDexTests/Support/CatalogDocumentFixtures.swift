import Foundation
@testable import Battle_Card_Dex

extension CatalogDocument {
    static func fixture(identifier: String = "creature-1", contentHash: String = "hash-1") throws -> Self {
        let payload = CatalogCreaturePayload(
            schemaVersion: 1,
            id: 1,
            name: "seed-creature",
            displayName: "Seed Creature",
            generation: "generation-1",
            types: ["leaf"],
            artworkURL: nil,
            genus: nil,
            description: nil,
            heightMetres: 0.7,
            weightKilograms: 6.9,
            baseExperience: nil,
            abilities: [],
            hiddenAbilities: [],
            stats: CatalogStats(hitPoints: 45, attack: 49, defense: 49, specialAttack: 65, specialDefense: 65, speed: 45),
            forms: [],
            moves: [],
            encounters: [],
            versionGroups: []
        )
        return try CatalogDocument(identifier: identifier, envelope: CatalogPersistenceEnvelope(payload), contentHash: contentHash)
    }
}
