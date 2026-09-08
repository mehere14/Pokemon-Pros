import Foundation

/// Provider-shaped values. These types exist only at the loader boundary and are
/// deliberately unsuitable for application storage or presentation.
nonisolated struct LoaderNamedResourceDTO: Decodable, Equatable, Sendable {
    let name: String?
    let url: String?
}

nonisolated struct LoaderCreatureDTO: Decodable, Equatable, Sendable {
    nonisolated struct TypeSlot: Decodable, Equatable, Sendable { let type: LoaderNamedResourceDTO? }
    nonisolated struct AbilitySlot: Decodable, Equatable, Sendable {
        let ability: LoaderNamedResourceDTO?
        let isHidden: Bool?
        enum CodingKeys: String, CodingKey { case ability; case isHidden = "is_hidden" }
    }
    nonisolated struct StatSlot: Decodable, Equatable, Sendable {
        let baseStat: Int?
        let stat: LoaderNamedResourceDTO?
        enum CodingKeys: String, CodingKey { case baseStat = "base_stat"; case stat }
    }
    nonisolated struct MoveSlot: Decodable, Equatable, Sendable {
        nonisolated struct VersionDetail: Decodable, Equatable, Sendable {
            let moveLearnMethod: LoaderNamedResourceDTO?
            let versionGroup: LoaderNamedResourceDTO?
            enum CodingKeys: String, CodingKey {
                case moveLearnMethod = "move_learn_method"
                case versionGroup = "version_group"
            }
        }
        let move: LoaderNamedResourceDTO?
        let versionGroupDetails: [VersionDetail]?
        enum CodingKeys: String, CodingKey {
            case move
            case versionGroupDetails = "version_group_details"
        }
    }

    let id: Int?
    let name: String?
    let height: Int?
    let weight: Int?
    let baseExperience: Int?
    let types: [TypeSlot]?
    let abilities: [AbilitySlot]?
    let stats: [StatSlot]?
    let moves: [MoveSlot]?

    enum CodingKeys: String, CodingKey {
        case id, name, height, weight, types, abilities, stats, moves
        case baseExperience = "base_experience"
    }
}

nonisolated struct LoaderEvolutionChainDTO: Decodable, Equatable, Sendable {
    nonisolated struct Detail: Decodable, Equatable, Sendable {
        let trigger: LoaderNamedResourceDTO?
        let minLevel: Int?
        let item: LoaderNamedResourceDTO?
        let heldItem: LoaderNamedResourceDTO?
        let tradeSpecies: LoaderNamedResourceDTO?
        let minHappiness: Int?
        let minAffection: Int?
        let minBeauty: Int?
        let timeOfDay: String?
        let location: LoaderNamedResourceDTO?
        let relativePhysicalStats: Int?
        let gender: Int?
        let knownMove: LoaderNamedResourceDTO?
        let knownMoveType: LoaderNamedResourceDTO?
        let partySpecies: LoaderNamedResourceDTO?
        let partyType: LoaderNamedResourceDTO?
        let needsOverworldRain: Bool?
        let turnUpsideDown: Bool?

        enum CodingKeys: String, CodingKey {
            case trigger, item, location, gender
            case minLevel = "min_level"
            case heldItem = "held_item"
            case tradeSpecies = "trade_species"
            case minHappiness = "min_happiness"
            case minAffection = "min_affection"
            case minBeauty = "min_beauty"
            case timeOfDay = "time_of_day"
            case relativePhysicalStats = "relative_physical_stats"
            case knownMove = "known_move"
            case knownMoveType = "known_move_type"
            case partySpecies = "party_species"
            case partyType = "party_type"
            case needsOverworldRain = "needs_overworld_rain"
            case turnUpsideDown = "turn_upside_down"
        }
    }

    nonisolated struct Link: Decodable, Equatable, Sendable {
        let species: LoaderNamedResourceDTO?
        let evolutionDetails: [Detail]?
        let evolvesTo: [Link]?
        enum CodingKeys: String, CodingKey {
            case species
            case evolutionDetails = "evolution_details"
            case evolvesTo = "evolves_to"
        }
    }

    let id: Int?
    let chain: Link?
}

nonisolated struct LoaderFormDTO: Decodable, Equatable, Sendable {
    nonisolated struct TypeSlot: Decodable, Equatable, Sendable { let type: LoaderNamedResourceDTO? }
    nonisolated struct Sprites: Decodable, Equatable, Sendable {
        let frontDefault: String?
        enum CodingKeys: String, CodingKey { case frontDefault = "front_default" }
    }
    let id: Int?
    let name: String?
    let isDefault: Bool?
    let types: [TypeSlot]?
    let sprites: Sprites?
    enum CodingKeys: String, CodingKey { case id, name, types, sprites; case isDefault = "is_default" }
}

nonisolated struct LoaderMoveDetailDTO: Decodable, Equatable, Sendable {
    nonisolated struct EffectEntry: Decodable, Equatable, Sendable {
        let effect: String?
        let language: LoaderNamedResourceDTO?
    }
    let id: Int?
    let name: String?
    let type: LoaderNamedResourceDTO?
    let damageClass: LoaderNamedResourceDTO?
    let power: Int?
    let accuracy: Int?
    let pp: Int?
    let priority: Int?
    let effectEntries: [EffectEntry]?
    enum CodingKeys: String, CodingKey {
        case id, name, type, power, accuracy, pp, priority
        case damageClass = "damage_class"
        case effectEntries = "effect_entries"
    }
}

nonisolated struct LoaderEncounterDTO: Decodable, Equatable, Sendable {
    nonisolated struct VersionDetail: Decodable, Equatable, Sendable {
        nonisolated struct Detail: Decodable, Equatable, Sendable {
            let minLevel: Int?
            let maxLevel: Int?
            let chance: Int?
            enum CodingKeys: String, CodingKey { case minLevel = "min_level"; case maxLevel = "max_level"; case chance }
        }
        let version: LoaderNamedResourceDTO?
        let maxChance: Int?
        let encounterDetails: [Detail]?
        enum CodingKeys: String, CodingKey { case version; case maxChance = "max_chance"; case encounterDetails = "encounter_details" }
    }
    let locationArea: LoaderNamedResourceDTO?
    let versionDetails: [VersionDetail]?
    enum CodingKeys: String, CodingKey { case locationArea = "location_area"; case versionDetails = "version_details" }
}

nonisolated struct LoaderBattleCardDTO: Decodable, Equatable, Sendable {
    nonisolated struct SetDTO: Decodable, Equatable, Sendable { let id: String?; let name: String? }
    nonisolated struct ImagesDTO: Decodable, Equatable, Sendable { let small: String?; let large: String? }
    nonisolated struct AbilityDTO: Decodable, Equatable, Sendable { let name: String?; let text: String?; let type: String? }
    nonisolated struct AttackDTO: Decodable, Equatable, Sendable { let name: String?; let text: String? }
    nonisolated struct ResistanceDTO: Decodable, Equatable, Sendable { let type: String?; let value: String? }

    let id: String?
    let name: String?
    let nationalIndexNumbers: [Int]?
    let set: SetDTO?
    let number: String?
    let rarity: String?
    let types: [String]?
    let hp: String?
    let images: ImagesDTO?
    let subtypes: [String]?
    let rules: [String]?
    let artist: String?
    let flavorText: String?
    let regulationMark: String?
    let legalities: [String: String]?
    let abilities: [AbilityDTO]?
    let attacks: [AttackDTO]?
    let weaknesses: [ResistanceDTO]?
    let resistances: [ResistanceDTO]?
    let retreatCost: [String]?
    let evolvesFrom: String?

    enum CodingKeys: String, CodingKey {
        case id, name, set, number, rarity, types, hp, images, subtypes, rules, artist, legalities
        case abilities, attacks, weaknesses, resistances, retreatCost, evolvesFrom
        case nationalIndexNumbers = "nationalPokedexNumbers"
        case flavorText = "flavorText"
        case regulationMark = "regulationMark"
    }
}
