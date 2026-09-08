import Foundation

nonisolated protocol NormalizedCatalogPayload: Codable, Equatable, Sendable {
    static var kind: CatalogPayloadKind { get }
    var schemaVersion: Int { get }
}

nonisolated enum CatalogPayloadKind: String, Codable, Equatable, Sendable {
    case manifest
    case creature
    case evolution
    case card
}

nonisolated struct CatalogManifestPayload: NormalizedCatalogPayload {
    static let kind = CatalogPayloadKind.manifest
    let schemaVersion: Int
    let id: String
    let revision: Int
    let publishedAt: Date
    let creatureCount: Int
    let evolutionCount: Int
    let cardCount: Int
    let contentHashes: [String: String]
}

nonisolated struct CatalogCreaturePayload: NormalizedCatalogPayload {
    static let kind = CatalogPayloadKind.creature
    let schemaVersion: Int
    let id: Int
    let name: String
    let displayName: String
    let generation: String?
    let types: [String]
    let artworkURL: URL?
    let genus: String?
    let description: String?
    let heightMetres: Double?
    let weightKilograms: Double?
    let baseExperience: Int?
    let abilities: [String]
    let hiddenAbilities: [String]
    let stats: CatalogStats
    let forms: [CatalogForm]
    let moves: [CatalogMove]
    let encounters: [CatalogEncounter]
    let versionGroups: [String]
    var cardRecordIdentifiers: [String]? = nil
    var evolutionRecordIdentifier: String? = nil
}

nonisolated struct CatalogStats: Codable, Equatable, Sendable {
    let hitPoints: Int
    let attack: Int
    let defense: Int
    let specialAttack: Int
    let specialDefense: Int
    let speed: Int
}

nonisolated struct CatalogForm: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let displayName: String
    let isDefault: Bool
    let types: [String]
    let artworkURL: URL?
}

nonisolated struct CatalogMove: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let displayName: String
    let versionGroups: [String]
    let learningMethods: [String]
    let type: String?
    let damageClass: String?
    let power: Int?
    let accuracy: Int?
    let powerPoints: Int?
    let priority: Int
    let effect: String?
}

nonisolated struct CatalogEncounter: Codable, Equatable, Sendable {
    let location: String
    let versionGroups: [String]
    let minimumLevel: Int?
    let maximumLevel: Int?
    let chancePercent: Int?
}

nonisolated struct CatalogEvolutionPayload: NormalizedCatalogPayload {
    static let kind = CatalogPayloadKind.evolution
    let schemaVersion: Int
    let id: Int
    let root: CatalogEvolutionNode
}

nonisolated struct CatalogEvolutionNode: Codable, Equatable, Sendable {
    let creatureID: Int
    let name: String
    let requirements: [CatalogEvolutionRequirement]
    let children: [CatalogEvolutionNode]
}

nonisolated struct CatalogEvolutionRequirement: Codable, Equatable, Sendable {
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

nonisolated struct CatalogCardPayload: NormalizedCatalogPayload {
    static let kind = CatalogPayloadKind.card
    let schemaVersion: Int
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

nonisolated enum CatalogEnvelopeError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case kindMismatch
    case rawPayloadRejected
    case unsafeText
}

/// The only byte representation accepted by persistence adapters. Its initializer
/// accepts normalized payload types, never provider DTOs.
nonisolated struct CatalogPersistenceEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let kind: CatalogPayloadKind
    let payload: Data

    init<Value: NormalizedCatalogPayload>(_ value: Value) throws {
        guard value.schemaVersion == 1 else { throw CatalogEnvelopeError.unsupportedSchema(value.schemaVersion) }
        schemaVersion = value.schemaVersion
        kind = Value.kind
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(value)
        guard Self.containsOnlySafeText(encoded) else { throw CatalogEnvelopeError.unsafeText }
        payload = encoded
    }

    func decode<Value: NormalizedCatalogPayload>(_ type: Value.Type) throws -> Value {
        guard schemaVersion == 1 else { throw CatalogEnvelopeError.unsupportedSchema(schemaVersion) }
        guard kind == Value.kind else { throw CatalogEnvelopeError.kindMismatch }
        return try JSONDecoder().decode(type, from: payload)
    }

    static func validatingPersistedBytes(_ data: Data) throws -> Self {
        let envelope: Self
        do { envelope = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw CatalogEnvelopeError.rawPayloadRejected }
        guard envelope.schemaVersion == 1 else { throw CatalogEnvelopeError.unsupportedSchema(envelope.schemaVersion) }
        guard containsOnlySafeText(envelope.payload) else { throw CatalogEnvelopeError.unsafeText }
        return envelope
    }

    private static func containsOnlySafeText(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        func isSafe(_ value: Any) -> Bool {
            if let string = value as? String { return !NeutralTextSanitizer.containsRestrictedBrand(in: string) }
            if let array = value as? [Any] { return array.allSatisfy(isSafe) }
            if let dictionary = value as? [String: Any] {
                return dictionary.allSatisfy { key, value in
                    guard !NeutralTextSanitizer.containsRestrictedBrand(in: key) else { return false }
                    // Provider/CDN URLs are transport identifiers, not authored
                    // catalog text. Their host or path can legitimately contain
                    // restricted branding, while every user-visible string must
                    // still pass the sanitizer. Restrict this exception to
                    // explicitly named HTTPS URL fields.
                    if key.hasSuffix("URL"), let string = value as? String {
                        guard let url = URL(string: string) else { return false }
                        return url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
                    }
                    return isSafe(value)
                }
            }
            return true
        }
        return isSafe(object)
    }
}
