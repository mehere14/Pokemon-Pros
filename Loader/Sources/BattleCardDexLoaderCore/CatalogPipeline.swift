import CryptoKit
import Foundation

public struct LoaderPipelineConfiguration: Sendable {
    public let creatureBaseURL: URL
    public let cardBaseURL: URL
    public let containerIdentifier: String
    public let checkpointURL: URL

    public init(
        creatureBaseURL: URL = URL(string: "https://pokeapi.co/api/v2/")!,
        cardBaseURL: URL = URL(string: "https://api.pokemontcg.io/v2/")!,
        containerIdentifier: String = "iCloud.com.askcruit.Battle-Card-Dex",
        checkpointURL: URL
    ) {
        self.creatureBaseURL = creatureBaseURL
        self.cardBaseURL = cardBaseURL
        self.containerIdentifier = containerIdentifier
        self.checkpointURL = checkpointURL
    }
}

public enum CatalogPipelineError: Error, Equatable, Sendable {
    case rangeRequired
    case invalidProviderPayload(String)
    case invalidCatalog(String)
    case unsupportedCommand
}

public struct LoaderCatalogBatch: Sendable {
    public let records: [LoaderRecord]
    public let manifest: LoaderRecord
    public let counts: [String: Int]
}

public actor FileLoaderCheckpointStore: LoaderCheckpointStore {
    private let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() async throws -> LoaderCheckpoint {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init() }
        return try JSONDecoder().decode(LoaderCheckpoint.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ checkpoint: LoaderCheckpoint) async throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(checkpoint).write(to: fileURL, options: [.atomic])
        #if canImport(Darwin)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        #endif
    }
}

public struct LiveCatalogPipeline: Sendable {
    private let configuration: LoaderPipelineConfiguration
    private let creatureHTTP: LoaderHTTPClient
    private let cardHTTP: LoaderHTTPClient
    private let cardAPIKey: String?
    private let now: @Sendable () -> Date

    public init(configuration: LoaderPipelineConfiguration, transport: any LoaderTransport = URLSessionLoaderTransport(),
                cardAPIKey: String?, now: @escaping @Sendable () -> Date = Date.init) {
        self.configuration = configuration
        creatureHTTP = LoaderHTTPClient(transport: transport, policy: .init(minimumRequestInterval: 0.1, maximumConcurrentRequests: 4))
        // Anonymous access is capped at 30/minute by the card provider. An API
        // key raises the documented daily allowance, while retries still honor
        // Retry-After for either mode.
        let cardInterval: TimeInterval = cardAPIKey == nil ? 2.1 : 0.2
        cardHTTP = LoaderHTTPClient(transport: transport, policy: .init(
            minimumRequestInterval: cardInterval,
            maximumConcurrentRequests: 1,
            maximumAttempts: 12,
            baseRetryDelay: 2,
            maximumRetryDelay: 300
        ))
        self.cardAPIKey = cardAPIKey
        self.now = now
    }

    public func build(range: IndexRange) async throws -> LoaderCatalogBatch {
        var creatures: [CreaturePayload] = []
        var evolutionByID: [Int: EvolutionPayload] = [:]
        var cardsByID: [String: CardPayload] = [:]
        for id in range.lowerBound...range.upperBound {
            try Task.checkCancellation()
            async let creature: ProviderCreature = fetchCreature(id)
            async let species: ProviderSpecies = fetchSpecies(id)
            async let encounters: [ProviderEncounter] = fetchEncounters(id)
            let (creatureValue, speciesValue, encounterValues) = try await (creature, species, encounters)
            var payload = try await makeCreature(creatureValue, species: speciesValue, encounters: encounterValues)
            if let chainID = Self.identifier(from: speciesValue.evolutionChain?.url), evolutionByID[chainID] == nil {
                let chain: ProviderEvolution = try await get("evolution-chain/\(chainID)")
                evolutionByID[chainID] = try makeEvolution(chain)
                payload.evolutionRecordIdentifier = "catalog-evolution-\(chainID)"
            } else if let chainID = Self.identifier(from: speciesValue.evolutionChain?.url) {
                payload.evolutionRecordIdentifier = "catalog-evolution-\(chainID)"
            }
            creatures.append(payload)
            for card in try await fetchCards(index: id) {
                var merged = cardsByID[card.id] ?? card
                merged.relatedCreatureIDs = Array(Set(merged.relatedCreatureIDs + [id])).sorted()
                cardsByID[card.id] = merged
            }
        }
        let evolutions = evolutionByID.values.sorted { $0.id < $1.id }
        let cards = cardsByID.values.sorted { $0.id < $1.id }
        let cardIdentifiersByCreature = Dictionary(grouping: cards.flatMap { card in
            card.relatedCreatureIDs.map { ($0, "catalog-card-\(Self.hash(Data(card.id.utf8)))") }
        }, by: \.0).mapValues { values in Array(Set(values.map(\.1))).sorted() }
        let orderedCreatures = creatures.map { creature in
            var indexed = creature
            indexed.cardRecordIdentifiers = cardIdentifiersByCreature[creature.id] ?? []
            return indexed
        }.sorted { $0.id < $1.id }
        try validate(creatures: orderedCreatures, evolutions: evolutions, cards: cards, range: range)
        return try encode(creatures: orderedCreatures, evolutions: evolutions, cards: cards, range: range)
    }

    public func discoverCatalogSize() async throws -> Int {
        let page: ProviderResourceCount = try await get("pokemon-species")
        guard page.count > 0 else { throw CatalogPipelineError.invalidProviderPayload("species-count") }
        return page.count
    }

    public func buildCreature(index: Int) async throws -> LoaderCatalogBatch {
        try await build(range: IndexRange(lowerBound: index, upperBound: index))
    }

    public func makeManifest(recordIndex: [String: FullCatalogRecordIndexEntry]) throws -> LoaderRecord {
        let timestamp = now()
        // Card identifiers are discovered with a paged CloudKit query. Keeping
        // thousands of card hashes in this payload would eventually exceed the
        // single-record ceiling; creature/evolution hashes remain compact and
        // preserve targeted refreshes for the primary catalog.
        let hashes = recordIndex.filter { $0.value.recordType != "CardCatalogRecord" }.mapValues(\.contentHash)
        let counts = Dictionary(grouping: recordIndex.values, by: \.recordType).mapValues(\.count)
        let value = ManifestPayload(
            schemaVersion: 1,
            id: "catalog-manifest",
            revision: Int(timestamp.timeIntervalSince1970),
            publishedAt: timestamp,
            creatureCount: counts["CreatureCatalogRecord", default: 0],
            evolutionCount: counts["EvolutionCatalogRecord", default: 0],
            cardCount: counts["CardCatalogRecord", default: 0],
            contentHashes: hashes
        )
        var ignored: [String: String] = [:]
        return try record(value, type: "CatalogManifest", name: "catalog-manifest-v1", fields: [
            "schemaVersion": .integer(1), "sourceIdentifier": .string("catalog-manifest"),
            "loaderTimestamp": .date(timestamp), "sourceTimestamp": .date(timestamp),
            "revision": .integer(Int64(value.revision)), "publishedAt": .date(timestamp),
            "creatureCount": .integer(Int64(value.creatureCount)),
            "evolutionCount": .integer(Int64(value.evolutionCount)),
            "cardCount": .integer(Int64(value.cardCount))
        ], hashes: &ignored, isManifest: true)
    }

    private func fetchCreature(_ id: Int) async throws -> ProviderCreature { try await get("pokemon/\(id)") }
    private func fetchSpecies(_ id: Int) async throws -> ProviderSpecies { try await get("pokemon-species/\(id)") }
    private func fetchEncounters(_ id: Int) async throws -> [ProviderEncounter] { try await get("pokemon/\(id)/encounters") }

    private func get<Value: Decodable>(_ path: String) async throws -> Value {
        do {
            return try await creatureHTTP.get(.init(url: configuration.creatureBaseURL.appendingPathComponent(path)), as: Value.self)
        } catch let LoaderHTTPError.httpStatus(status, _) {
            throw CatalogPipelineError.invalidProviderPayload("http-\(status)-\(path.replacingOccurrences(of: "/", with: "-"))")
        }
    }

    private func makeCreature(_ source: ProviderCreature, species: ProviderSpecies, encounters: [ProviderEncounter]) async throws -> CreaturePayload {
        guard let id = source.id, id > 0, let name = Self.name(source.name) else { throw CatalogPipelineError.invalidProviderPayload("creature") }
        var moves: [MovePayload] = []
        for entry in source.moves ?? [] {
            guard let moveID = Self.identifier(from: entry.move?.url), let moveName = Self.name(entry.move?.name) else { continue }
            let detail: ProviderMove? = try? await get("move/\(moveID)")
            let groups = Array(Set((entry.versionGroupDetails ?? []).compactMap { Self.name($0.versionGroup?.name) })).sorted()
            let methods = Array(Set((entry.versionGroupDetails ?? []).compactMap { Self.name($0.moveLearnMethod?.name) })).sorted()
            moves.append(.init(id: moveID, name: moveName, displayName: Self.display(moveName), versionGroups: groups,
                               learningMethods: methods, type: Self.name(detail?.type?.name), damageClass: Self.name(detail?.damageClass?.name),
                               power: detail?.power, accuracy: detail?.accuracy, powerPoints: detail?.pp, priority: detail?.priority ?? 0,
                               effect: Self.safe(detail?.effectEntries?.first(where: { $0.language?.name == "en" })?.shortEffect)))
        }
        let englishFlavor = species.flavorTextEntries?.first(where: { $0.language?.name == "en" })?.flavorText
        let genus = species.genera?.first(where: { $0.language?.name == "en" })?.genus
        let forms = (source.forms ?? []).compactMap { item -> FormPayload? in
            guard let formID = Self.identifier(from: item.url), let formName = Self.name(item.name) else { return nil }
            return .init(id: formID, name: formName, displayName: Self.display(formName), isDefault: formID == id,
                         types: [], artworkURL: nil)
        }
        let statPairs: [(String, Int)] = (source.stats ?? []).compactMap { slot in
            guard let key = Self.name(slot.stat?.name), let value = slot.baseStat else { return nil }; return (key, value)
        }
        let stats = Dictionary(uniqueKeysWithValues: statPairs)
        return CreaturePayload(schemaVersion: 1, id: id, name: name, displayName: Self.display(name),
            generation: Self.name(species.generation?.name), types: (source.types ?? []).compactMap { Self.name($0.type?.name) },
            artworkURL: source.sprites?.other?.officialArtwork?.frontDefault.flatMap(URL.init(string:)), genus: Self.safe(genus),
            description: Self.safe(englishFlavor), heightMetres: source.height.map { Double($0) / 10 },
            weightKilograms: source.weight.map { Double($0) / 10 }, baseExperience: source.baseExperience,
            abilities: (source.abilities ?? []).filter { $0.isHidden != true }.compactMap { Self.name($0.ability?.name) },
            hiddenAbilities: (source.abilities ?? []).filter { $0.isHidden == true }.compactMap { Self.name($0.ability?.name) },
            stats: .init(hitPoints: stats["hp"] ?? 0, attack: stats["attack"] ?? 0, defense: stats["defense"] ?? 0,
                         specialAttack: stats["special-attack"] ?? 0, specialDefense: stats["special-defense"] ?? 0, speed: stats["speed"] ?? 0),
            forms: forms, moves: moves.sorted { $0.id < $1.id }, encounters: encounters.compactMap(Self.encounter),
            versionGroups: Array(Set(moves.flatMap(\.versionGroups))).sorted())
    }

    private func makeEvolution(_ source: ProviderEvolution) throws -> EvolutionPayload {
        guard let id = source.id, id > 0, let chain = source.chain else { throw CatalogPipelineError.invalidProviderPayload("evolution") }
        func node(_ value: ProviderEvolution.Link) throws -> EvolutionNodePayload {
            guard let creatureID = Self.identifier(from: value.species?.url), let name = Self.name(value.species?.name) else {
                throw CatalogPipelineError.invalidProviderPayload("evolution-member")
            }
            return .init(creatureID: creatureID, name: name, requirements: (value.evolutionDetails ?? []).map {
                .init(trigger: Self.name($0.trigger?.name), minimumLevel: $0.minLevel, item: Self.name($0.item?.name),
                      heldItem: Self.name($0.heldItem?.name), tradeSpecies: Self.name($0.tradeSpecies?.name),
                      minimumHappiness: $0.minHappiness, minimumAffection: $0.minAffection, minimumBeauty: $0.minBeauty,
                      timeOfDay: Self.name($0.timeOfDay), location: Self.name($0.location?.name),
                      weather: $0.needsOverworldRain == true ? "rain" : nil, relativePhysicalStats: $0.relativePhysicalStats,
                      gender: $0.gender == 1 ? "female" : ($0.gender == 2 ? "male" : nil), knownMove: Self.name($0.knownMove?.name),
                      knownMoveType: Self.name($0.knownMoveType?.name), partySpecies: Self.name($0.partySpecies?.name),
                      partyType: Self.name($0.partyType?.name), needsUpsideDownDevice: $0.turnUpsideDown == true)
            }, children: try (value.evolvesTo ?? []).map(node))
        }
        return .init(schemaVersion: 1, id: id, root: try node(chain))
    }

    private func fetchCards(index: Int) async throws -> [CardPayload] {
        var page = 1
        var result: [CardPayload] = []
        while true {
            var components = URLComponents(url: configuration.cardBaseURL.appendingPathComponent("cards"), resolvingAgainstBaseURL: false)!
            components.queryItems = [.init(name: "q", value: "nationalPokedexNumbers:\(index)"), .init(name: "page", value: String(page)), .init(name: "pageSize", value: "250")]
            var headers: [String: String] = [:]
            if let cardAPIKey { headers["X-Api-Key"] = cardAPIKey }
            let response: ProviderCardPage
            do { response = try await cardHTTP.get(.init(url: components.url!, headers: headers), as: ProviderCardPage.self) }
            catch let LoaderHTTPError.httpStatus(status, _) {
                throw CatalogPipelineError.invalidProviderPayload("http-\(status)-cards-index-\(index)-page-\(page)")
            }
            result.append(contentsOf: (response.data ?? []).compactMap { Self.card($0, relatedID: index) })
            let received = (response.page ?? page) * (response.pageSize ?? 250)
            guard received < (response.totalCount ?? result.count) else { return result }
            page += 1
        }
    }

    private func validate(creatures: [CreaturePayload], evolutions: [EvolutionPayload], cards: [CardPayload], range: IndexRange) throws {
        guard creatures.count == range.count, Set(creatures.map(\.id)).count == creatures.count else { throw CatalogPipelineError.invalidCatalog("creature-count") }
        let chainMembers = Set(evolutions.flatMap { $0.memberIDs })
        guard creatures.allSatisfy({ chainMembers.contains($0.id) }) else { throw CatalogPipelineError.invalidCatalog("missing-evolution") }
        guard cards.allSatisfy({ !$0.relatedCreatureIDs.isEmpty && $0.smallImageURL != nil && $0.largeImageURL != nil }) else {
            throw CatalogPipelineError.invalidCatalog("card-reference")
        }
        let cardMembers = Set(cards.flatMap(\.relatedCreatureIDs))
        guard creatures.allSatisfy({ cardMembers.contains($0.id) }) else {
            throw CatalogPipelineError.invalidCatalog("missing-creature-cards")
        }
        guard creatures.allSatisfy({ !($0.cardRecordIdentifiers ?? []).isEmpty }) else {
            throw CatalogPipelineError.invalidCatalog("missing-creature-card-index")
        }
    }

    private func encode(creatures: [CreaturePayload], evolutions: [EvolutionPayload], cards: [CardPayload], range: IndexRange) throws -> LoaderCatalogBatch {
        let timestamp = now()
        var hashes: [String: String] = [:]
        let creatureRecords = try creatures.map { try record($0, type: "CreatureCatalogRecord", name: "catalog-creature-\($0.id)", fields: [
            "schemaVersion": .integer(1), "sourceIdentifier": .integer(Int64($0.id)), "loaderTimestamp": .date(timestamp),
            "normalizedName": .string($0.name), "displayName": .string($0.displayName), "types": .strings($0.types)
        ].merging($0.generation.map { ["generation": .string($0)] } ?? [:]) { current, _ in current }, hashes: &hashes) }
        let evolutionRecords = try evolutions.map { try record($0, type: "EvolutionCatalogRecord", name: "catalog-evolution-\($0.id)", fields: [
            "schemaVersion": .integer(1), "sourceIdentifier": .integer(Int64($0.id)), "loaderTimestamp": .date(timestamp),
            "memberIdentifiers": .integers($0.memberIDs.map(Int64.init))
        ], hashes: &hashes) }
        let cardRecords = try cards.map { card -> LoaderRecord in
            let name = "catalog-card-\(Self.hash(Data(card.id.utf8)))"
            return try record(card, type: "CardCatalogRecord", name: name, fields: [
                "schemaVersion": .integer(1), "sourceIdentifier": .string(card.id), "loaderTimestamp": .date(timestamp),
                "normalizedName": .string(card.name.lowercased()), "displayName": .string(card.name), "setIdentifier": .string(card.setID),
                "collectorNumber": .string(card.collectorNumber), "types": .strings(card.types),
                "relatedCreatureIdentifiers": .integers(card.relatedCreatureIDs.map(Int64.init))
            ], hashes: &hashes)
        }
        let manifestValue = ManifestPayload(schemaVersion: 1, id: "catalog-manifest", revision: Int(timestamp.timeIntervalSince1970),
            publishedAt: timestamp, creatureCount: creatures.count, evolutionCount: evolutions.count, cardCount: cards.count, contentHashes: hashes)
        let manifest = try record(manifestValue, type: "CatalogManifest", name: "catalog-manifest-v1", fields: [
            "schemaVersion": .integer(1), "sourceIdentifier": .string("catalog-manifest"), "loaderTimestamp": .date(timestamp),
            "sourceTimestamp": .date(timestamp), "revision": .integer(Int64(manifestValue.revision)), "publishedAt": .date(timestamp),
            "creatureCount": .integer(Int64(creatures.count)), "evolutionCount": .integer(Int64(evolutions.count)), "cardCount": .integer(Int64(cards.count))
        ], hashes: &hashes, isManifest: true)
        return .init(records: creatureRecords + evolutionRecords + cardRecords, manifest: manifest,
                     counts: ["creatures": creatures.count, "evolutions": evolutions.count, "cards": cards.count])
    }

    private func record<Value: Encodable>(_ value: Value, type: String, name: String, fields: [String: LoaderRecordField],
                                          hashes: inout [String: String], isManifest: Bool = false) throws -> LoaderRecord {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let inner = try encoder.encode(value)
        let envelope = PersistenceEnvelope(schemaVersion: 1, kind: isManifest ? "manifest" : type == "CreatureCatalogRecord" ? "creature" : type == "EvolutionCatalogRecord" ? "evolution" : "card", payload: inner)
        let payload = try encoder.encode(envelope)
        guard payload.count <= 900 * 1_024 else { throw CatalogPipelineError.invalidCatalog("record-size") }
        let hash = Self.hash(payload); if !isManifest { hashes[name] = hash }
        return .init(identifier: name, recordType: type, contentHash: hash, payload: payload, fields: fields, isManifest: isManifest)
    }

    private static func identifier(from url: String?) -> Int? { url?.split(separator: "/").reversed().compactMap { Int($0) }.first }
    private static func name(_ value: String?) -> String? {
        let normalized = safe(value)?.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-") ?? ""
        return normalized.isEmpty ? nil : normalized
    }
    private static func display(_ value: String) -> String { value.split(separator: "-").map { $0.capitalized }.joined(separator: " ") }
    private static func safe(_ value: String?) -> String? {
        guard var text = value?.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\u{000C}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let scalars = [112,111,107,101,109,111,110].compactMap(UnicodeScalar.init).map(String.init).joined()
        text = text.replacingOccurrences(of: scalars, with: "creature", options: [.caseInsensitive, .diacriticInsensitive])
        return text
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func encounter(_ value: ProviderEncounter) -> EncounterPayload? {
        guard let location = name(value.locationArea?.name) else { return nil }
        let details = (value.versionDetails ?? []).flatMap(\.encounterDetails)
        return .init(location: location, versionGroups: (value.versionDetails ?? []).compactMap { name($0.version?.name) },
                     minimumLevel: details.compactMap(\.minLevel).min(), maximumLevel: details.compactMap(\.maxLevel).max(),
                     chancePercent: details.compactMap(\.chance).max())
    }
    private static func card(_ source: ProviderCard, relatedID: Int) -> CardPayload? {
        guard let id = safe(source.id), let name = safe(source.name), let setID = safe(source.set?.id), let setName = safe(source.set?.name),
              let number = safe(source.number) else { return nil }
        let relatedIDs = Array(Set((source.nationalPokedexNumbers ?? []) + [relatedID])).filter { $0 > 0 }.sorted()
        return .init(schemaVersion: 1, id: id, relatedCreatureIDs: relatedIDs, name: name, setID: setID, setName: setName,
            collectorNumber: number, rarity: safe(source.rarity), types: source.types?.compactMap(Self.name) ?? [], hitPoints: source.hp.flatMap(Int.init),
            smallImageURL: source.images?.small.flatMap(URL.init(string:)), largeImageURL: source.images?.large.flatMap(URL.init(string:)),
            subtypes: source.subtypes?.compactMap(Self.safe) ?? [], rules: source.rules?.compactMap(Self.safe) ?? [],
            abilities: source.abilities?.compactMap { safe([$0.name, $0.text].compactMap { $0 }.joined(separator: " — ")) } ?? [],
            attacks: source.attacks?.compactMap { safe([$0.name, $0.damage, $0.text].compactMap { $0 }.joined(separator: " — ")) } ?? [],
            weaknesses: source.weaknesses?.compactMap { safe([$0.type, $0.value].compactMap { $0 }.joined(separator: " — ")) } ?? [],
            resistances: source.resistances?.compactMap { safe([$0.type, $0.value].compactMap { $0 }.joined(separator: " — ")) } ?? [],
            retreatCost: source.retreatCost?.compactMap(Self.name) ?? [], evolutionText: safe(source.evolvesFrom), artist: safe(source.artist),
            flavorText: safe(source.flavorText), regulationMark: safe(source.regulationMark), legalities: source.legalities ?? [:])
    }
}

private struct Named: Decodable { let name: String?; let url: String? }
private struct ProviderCreature: Decodable {
    struct TypeSlot: Decodable { let type: Named? }; struct AbilitySlot: Decodable { let ability: Named?; let isHidden: Bool?; enum CodingKeys: String, CodingKey { case ability; case isHidden = "is_hidden" } }
    struct StatSlot: Decodable { let baseStat: Int?; let stat: Named?; enum CodingKeys: String, CodingKey { case baseStat = "base_stat"; case stat } }
    struct MoveSlot: Decodable { struct Detail: Decodable { let moveLearnMethod: Named?; let versionGroup: Named?; enum CodingKeys: String, CodingKey { case moveLearnMethod = "move_learn_method"; case versionGroup = "version_group" } }; let move: Named?; let versionGroupDetails: [Detail]?; enum CodingKeys: String, CodingKey { case move; case versionGroupDetails = "version_group_details" } }
    struct Sprites: Decodable { struct Other: Decodable { struct Artwork: Decodable { let frontDefault: String?; enum CodingKeys: String, CodingKey { case frontDefault = "front_default" } }; let officialArtwork: Artwork?; enum CodingKeys: String, CodingKey { case officialArtwork = "official-artwork" } }; let other: Other? }
    let id: Int?; let name: String?; let height: Int?; let weight: Int?; let baseExperience: Int?; let types: [TypeSlot]?; let abilities: [AbilitySlot]?; let stats: [StatSlot]?; let moves: [MoveSlot]?; let forms: [Named]?; let sprites: Sprites?
    enum CodingKeys: String, CodingKey { case id,name,height,weight,types,abilities,stats,moves,forms,sprites; case baseExperience = "base_experience" }
}
private struct ProviderSpecies: Decodable {
    struct Flavor: Decodable { let flavorText: String?; let language: Named?; enum CodingKeys: String, CodingKey { case flavorText = "flavor_text"; case language } }; struct Genus: Decodable { let genus: String?; let language: Named? }
    let evolutionChain: Named?; let generation: Named?; let flavorTextEntries: [Flavor]?; let genera: [Genus]?
    enum CodingKeys: String, CodingKey { case evolutionChain = "evolution_chain"; case generation; case flavorTextEntries = "flavor_text_entries"; case genera }
}
private struct ProviderMove: Decodable { struct Effect: Decodable { let shortEffect: String?; let language: Named?; enum CodingKeys: String, CodingKey { case shortEffect = "short_effect"; case language } }; let type: Named?; let damageClass: Named?; let power: Int?; let accuracy: Int?; let pp: Int?; let priority: Int?; let effectEntries: [Effect]?; enum CodingKeys: String, CodingKey { case type,power,accuracy,pp,priority; case damageClass = "damage_class"; case effectEntries = "effect_entries" } }
private struct ProviderEncounter: Decodable { struct Version: Decodable { struct Detail: Decodable { let minLevel: Int?; let maxLevel: Int?; let chance: Int?; enum CodingKeys: String, CodingKey { case minLevel = "min_level"; case maxLevel = "max_level"; case chance } }; let version: Named?; let encounterDetails: [Detail]; enum CodingKeys: String, CodingKey { case version; case encounterDetails = "encounter_details" } }; let locationArea: Named?; let versionDetails: [Version]?; enum CodingKeys: String, CodingKey { case locationArea = "location_area"; case versionDetails = "version_details" } }
private struct ProviderEvolution: Decodable { struct Link: Decodable { struct Detail: Decodable { let trigger,item,heldItem,tradeSpecies,location,knownMove,knownMoveType,partySpecies,partyType: Named?; let minLevel,minHappiness,minAffection,minBeauty,relativePhysicalStats,gender: Int?; let timeOfDay: String?; let needsOverworldRain,turnUpsideDown: Bool?; enum CodingKeys: String, CodingKey { case trigger,item,location,gender; case heldItem="held_item",tradeSpecies="trade_species",minLevel="min_level",minHappiness="min_happiness",minAffection="min_affection",minBeauty="min_beauty",relativePhysicalStats="relative_physical_stats",timeOfDay="time_of_day",knownMove="known_move",knownMoveType="known_move_type",partySpecies="party_species",partyType="party_type",needsOverworldRain="needs_overworld_rain",turnUpsideDown="turn_upside_down" } }; let species: Named?; let evolutionDetails: [Detail]?; let evolvesTo: [Link]?; enum CodingKeys: String, CodingKey { case species; case evolutionDetails="evolution_details",evolvesTo="evolves_to" } }; let id: Int?; let chain: Link? }
private struct ProviderCardPage: Decodable { let data: [ProviderCard]?; let page,pageSize,totalCount: Int? }
private struct ProviderResourceCount: Decodable { let count: Int }
private struct ProviderCard: Decodable { struct SetValue: Decodable { let id,name: String? }; struct Images: Decodable { let small,large: String? }; struct TextPart: Decodable { let name,text,damage,type,value: String? }; let id,name,hp,number,rarity,evolvesFrom,artist,flavorText,regulationMark: String?; let set: SetValue?; let images: Images?; let types,subtypes,rules,retreatCost: [String]?; let abilities,attacks,weaknesses,resistances: [TextPart]?; let legalities: [String:String]?; let nationalPokedexNumbers: [Int]?; enum CodingKeys: String, CodingKey { case id,name,hp,number,rarity,set,images,types,subtypes,rules,abilities,attacks,weaknesses,resistances,legalities,artist,nationalPokedexNumbers; case evolvesFrom="evolvesFrom",flavorText="flavorText",regulationMark="regulationMark",retreatCost="retreatCost" } }

private struct PersistenceEnvelope: Codable { let schemaVersion: Int; let kind: String; let payload: Data }
private struct ManifestPayload: Codable { let schemaVersion: Int; let id: String; let revision: Int; let publishedAt: Date; let creatureCount,evolutionCount,cardCount: Int; let contentHashes: [String:String] }
private struct CreaturePayload: Codable { let schemaVersion,id: Int; let name,displayName: String; let generation: String?; let types: [String]; let artworkURL: URL?; let genus,description: String?; let heightMetres,weightKilograms: Double?; let baseExperience: Int?; let abilities,hiddenAbilities: [String]; let stats: StatsPayload; let forms: [FormPayload]; let moves: [MovePayload]; let encounters: [EncounterPayload]; let versionGroups: [String]; var cardRecordIdentifiers: [String]? = nil; var evolutionRecordIdentifier: String? = nil }
private struct StatsPayload: Codable { let hitPoints,attack,defense,specialAttack,specialDefense,speed: Int }
private struct FormPayload: Codable { let id: Int; let name,displayName: String; let isDefault: Bool; let types:[String]; let artworkURL: URL? }
private struct MovePayload: Codable { let id:Int; let name,displayName:String; let versionGroups,learningMethods:[String]; let type,damageClass:String?; let power,accuracy,powerPoints:Int?; let priority:Int; let effect:String? }
private struct EncounterPayload: Codable { let location:String; let versionGroups:[String]; let minimumLevel,maximumLevel,chancePercent:Int? }
private struct EvolutionPayload: Codable { let schemaVersion,id:Int; let root:EvolutionNodePayload; var memberIDs:[Int] { func collect(_ node:EvolutionNodePayload)->[Int] { [node.creatureID] + node.children.flatMap(collect) }; return collect(root).sorted() } }
private struct EvolutionNodePayload: Codable { let creatureID:Int; let name:String; let requirements:[EvolutionRequirementPayload]; let children:[EvolutionNodePayload] }
private struct EvolutionRequirementPayload: Codable { let trigger:String?; let minimumLevel:Int?; let item,heldItem,tradeSpecies:String?; let minimumHappiness,minimumAffection,minimumBeauty:Int?; let timeOfDay,location,weather:String?; let relativePhysicalStats:Int?; let gender,knownMove,knownMoveType,partySpecies,partyType:String?; let needsUpsideDownDevice:Bool }
private struct CardPayload: Codable { let schemaVersion:Int; let id:String; var relatedCreatureIDs:[Int]; let name,setID,setName,collectorNumber:String; let rarity:String?; let types:[String]; let hitPoints:Int?; let smallImageURL,largeImageURL:URL?; let subtypes,rules,abilities,attacks,weaknesses,resistances,retreatCost:[String]; let evolutionText,artist,flavorText,regulationMark:String?; let legalities:[String:String] }
