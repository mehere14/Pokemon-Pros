import Foundation

nonisolated enum CatalogMappingError: Error, Equatable, Sendable {
    case missingRequiredField(String)
    case invalidIdentifier(String)
    case unsafeRequiredText(String)
}

nonisolated enum NeutralTextSanitizer {
    enum UnsafeTextPolicy { case rewriteAsCreature; case omit }

    static func sanitize(_ value: String?, policy: UnsafeTextPolicy) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        guard containsRestrictedBrand(in: value) else { return value }
        switch policy {
        case .rewriteAsCreature: return "Creature"
        case .omit: return nil
        }
    }

    static func containsRestrictedBrand(in value: String) -> Bool {
        let prohibited = String(String.UnicodeScalarView([112, 111, 107, 101, 109, 111, 110].compactMap(UnicodeScalar.init)))
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(folded)).contains(prohibited)
    }
}

nonisolated enum CatalogNormalizer {
    static func creature(from dto: LoaderCreatureDTO) throws -> CatalogCreaturePayload {
        let id = try positiveID(dto.id, field: "creature.id")
        let name = try requiredName(dto.name, field: "creature.name")
        let typeNames = normalizedUnique(dto.types?.compactMap { $0.type?.name } ?? [])
        let abilities = dto.abilities ?? []
        let ordinaryAbilities = normalizedUnique(abilities.filter { $0.isHidden != true }.compactMap { $0.ability?.name })
        let hiddenAbilities = normalizedUnique(abilities.filter { $0.isHidden == true }.compactMap { $0.ability?.name })
        let statPairs = (dto.stats ?? []).compactMap { slot -> (String, Int)? in
            guard let name = normalizedName(slot.stat?.name), let value = slot.baseStat else { return nil }
            return (name, max(0, value))
        }
        let statValues = statPairs.reduce(into: [String: Int]()) { $0[$1.0] = $1.1 }
        let moves = (dto.moves ?? []).compactMap { slot -> CatalogMove? in
            guard let moveName = normalizedName(slot.move?.name), let moveID = sourceID(from: slot.move?.url) else { return nil }
            let details = slot.versionGroupDetails ?? []
            return CatalogMove(
                id: moveID,
                name: moveName,
                displayName: displayName(moveName),
                versionGroups: normalizedUnique(details.compactMap { $0.versionGroup?.name }),
                learningMethods: normalizedUnique(details.compactMap { $0.moveLearnMethod?.name }),
                type: nil, damageClass: nil, power: nil, accuracy: nil, powerPoints: nil, priority: 0, effect: nil
            )
        }.sorted { $0.id < $1.id }

        return CatalogCreaturePayload(
            schemaVersion: 1, id: id, name: name, displayName: displayName(name), generation: nil,
            types: typeNames, artworkURL: nil, genus: nil, description: nil,
            heightMetres: nonnegative(dto.height).map { Double($0) / 10.0 },
            weightKilograms: nonnegative(dto.weight).map { Double($0) / 10.0 },
            baseExperience: nonnegative(dto.baseExperience), abilities: ordinaryAbilities,
            hiddenAbilities: hiddenAbilities,
            stats: CatalogStats(
                hitPoints: statValues["hp"] ?? 0, attack: statValues["attack"] ?? 0,
                defense: statValues["defense"] ?? 0, specialAttack: statValues["special-attack"] ?? 0,
                specialDefense: statValues["special-defense"] ?? 0, speed: statValues["speed"] ?? 0
            ), forms: [], moves: moves, encounters: [],
            versionGroups: normalizedUnique(moves.flatMap(\.versionGroups))
        )
    }

    static func evolution(from dto: LoaderEvolutionChainDTO) throws -> CatalogEvolutionPayload {
        let id = try positiveID(dto.id, field: "evolution.id")
        guard let chain = dto.chain else { throw CatalogMappingError.missingRequiredField("evolution.chain") }
        return CatalogEvolutionPayload(schemaVersion: 1, id: id, root: try evolutionNode(from: chain))
    }

    static func form(from dto: LoaderFormDTO) throws -> CatalogForm {
        let id = try positiveID(dto.id, field: "form.id")
        let name = try requiredName(dto.name, field: "form.name")
        return CatalogForm(
            id: id,
            name: name,
            displayName: displayName(name),
            isDefault: dto.isDefault == true,
            types: normalizedUnique(dto.types?.compactMap { $0.type?.name } ?? []),
            artworkURL: validURL(dto.sprites?.frontDefault)
        )
    }

    static func move(from dto: LoaderMoveDetailDTO, versionGroups: [String] = [], learningMethods: [String] = []) throws -> CatalogMove {
        let id = try positiveID(dto.id, field: "move.id")
        let name = try requiredName(dto.name, field: "move.name")
        let effect = dto.effectEntries?
            .first { normalizedName($0.language?.name) == "en" }
            .flatMap { NeutralTextSanitizer.sanitize($0.effect, policy: .omit) }
        return CatalogMove(
            id: id, name: name, displayName: displayName(name),
            versionGroups: normalizedUnique(versionGroups), learningMethods: normalizedUnique(learningMethods),
            type: normalizedName(dto.type?.name), damageClass: normalizedName(dto.damageClass?.name),
            power: nonnegative(dto.power), accuracy: nonnegative(dto.accuracy), powerPoints: nonnegative(dto.pp),
            priority: dto.priority ?? 0, effect: effect
        )
    }

    static func encounters(from dtos: [LoaderEncounterDTO]) -> [CatalogEncounter] {
        dtos.flatMap { dto -> [CatalogEncounter] in
            guard let location = normalizedName(dto.locationArea?.name) else { return [] }
            return (dto.versionDetails ?? []).map { version in
                let details = version.encounterDetails ?? []
                return CatalogEncounter(
                    location: location,
                    versionGroups: normalizedUnique([version.version?.name].compactMap { $0 }),
                    minimumLevel: details.compactMap { nonnegative($0.minLevel) }.min(),
                    maximumLevel: details.compactMap { nonnegative($0.maxLevel) }.max(),
                    chancePercent: nonnegative(version.maxChance ?? details.compactMap(\.chance).max())
                )
            }
        }.sorted {
            ($0.location, $0.versionGroups.joined()) < ($1.location, $1.versionGroups.joined())
        }
    }

    static func card(from dto: LoaderBattleCardDTO) throws -> CatalogCardPayload {
        guard let id = cleanID(dto.id) else { throw CatalogMappingError.invalidIdentifier("card.id") }
        let name = try requiredSafeText(dto.name, field: "card.name")
        guard let setID = cleanID(dto.set?.id) else { throw CatalogMappingError.invalidIdentifier("card.set.id") }
        let setName = try requiredSafeText(dto.set?.name, field: "card.set.name")
        guard let number = cleanID(dto.number) else { throw CatalogMappingError.invalidIdentifier("card.number") }
        return CatalogCardPayload(
            schemaVersion: 1, id: id, relatedCreatureIDs: Array(Set((dto.nationalIndexNumbers ?? []).filter { $0 > 0 })).sorted(),
            name: name, setID: setID, setName: setName, collectorNumber: number,
            rarity: NeutralTextSanitizer.sanitize(dto.rarity, policy: .omit),
            types: normalizedUnique(dto.types ?? []), hitPoints: dto.hp.flatMap(Int.init).flatMap(nonnegative),
            smallImageURL: validURL(dto.images?.small), largeImageURL: validURL(dto.images?.large),
            subtypes: normalizedUnique(dto.subtypes ?? []), rules: sanitizedList(dto.rules ?? []),
            abilities: sanitizedComponents(dto.abilities ?? []) { [$0.name, $0.type, $0.text] },
            attacks: sanitizedComponents(dto.attacks ?? []) { [$0.name, $0.text] },
            weaknesses: sanitizedComponents(dto.weaknesses ?? []) { [$0.type, $0.value] },
            resistances: sanitizedComponents(dto.resistances ?? []) { [$0.type, $0.value] },
            retreatCost: normalizedUnique(dto.retreatCost ?? []),
            evolutionText: NeutralTextSanitizer.sanitize(dto.evolvesFrom, policy: .omit),
            artist: NeutralTextSanitizer.sanitize(dto.artist, policy: .omit),
            flavorText: NeutralTextSanitizer.sanitize(dto.flavorText, policy: .omit),
            regulationMark: NeutralTextSanitizer.sanitize(dto.regulationMark, policy: .omit),
            legalities: Dictionary(uniqueKeysWithValues: (dto.legalities ?? [:]).compactMap { key, value in
                guard let cleanKey = normalizedName(key), let cleanValue = NeutralTextSanitizer.sanitize(value, policy: .omit) else { return nil }
                return (cleanKey, cleanValue)
            })
        )
    }

    private static func evolutionNode(from link: LoaderEvolutionChainDTO.Link) throws -> CatalogEvolutionNode {
        let name = try requiredName(link.species?.name, field: "evolution.species.name")
        guard let id = sourceID(from: link.species?.url), id > 0 else { throw CatalogMappingError.invalidIdentifier("evolution.species.url") }
        let requirements = (link.evolutionDetails ?? []).map { detail in
            CatalogEvolutionRequirement(
                trigger: normalizedName(detail.trigger?.name), minimumLevel: nonnegative(detail.minLevel),
                item: normalizedName(detail.item?.name), heldItem: normalizedName(detail.heldItem?.name),
                tradeSpecies: normalizedName(detail.tradeSpecies?.name), minimumHappiness: nonnegative(detail.minHappiness),
                minimumAffection: nonnegative(detail.minAffection), minimumBeauty: nonnegative(detail.minBeauty),
                timeOfDay: normalizedName(detail.timeOfDay), location: normalizedName(detail.location?.name),
                weather: detail.needsOverworldRain == true ? "rain" : nil,
                relativePhysicalStats: detail.relativePhysicalStats,
                gender: normalizedGender(detail.gender), knownMove: normalizedName(detail.knownMove?.name),
                knownMoveType: normalizedName(detail.knownMoveType?.name), partySpecies: normalizedName(detail.partySpecies?.name),
                partyType: normalizedName(detail.partyType?.name), needsUpsideDownDevice: detail.turnUpsideDown == true
            )
        }
        let children = try (link.evolvesTo ?? []).map(evolutionNode(from:))
        return CatalogEvolutionNode(creatureID: id, name: name, requirements: requirements, children: children)
    }

    static func normalizedName(_ value: String?) -> String? {
        guard let safe = NeutralTextSanitizer.sanitize(value, policy: .omit) else { return nil }
        let parts = safe.lowercased().split { !$0.isLetter && !$0.isNumber }
        let result = parts.joined(separator: "-")
        return result.isEmpty ? nil : result
    }

    static func displayName(_ normalized: String) -> String {
        normalized.split(separator: "-").map { part in part.prefix(1).uppercased() + part.dropFirst() }.joined(separator: " ")
    }

    private static func requiredName(_ value: String?, field: String) throws -> String {
        guard let result = normalizedName(value) else { throw CatalogMappingError.missingRequiredField(field) }
        return result
    }

    private static func requiredSafeText(_ value: String?, field: String) throws -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            throw CatalogMappingError.missingRequiredField(field)
        }
        guard let result = NeutralTextSanitizer.sanitize(trimmed, policy: .omit) else {
            throw CatalogMappingError.unsafeRequiredText(field)
        }
        return result
    }

    private static func positiveID(_ value: Int?, field: String) throws -> Int {
        guard let value, value > 0 else { throw CatalogMappingError.invalidIdentifier(field) }
        return value
    }

    private static func sourceID(from value: String?) -> Int? {
        value?.split(separator: "/").reversed().compactMap { Int($0) }.first
    }

    private static func cleanID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./")).contains($0) })
        else { return nil }
        return value
    }

    private static func nonnegative(_ value: Int?) -> Int? { value.flatMap { $0 >= 0 ? $0 : nil } }
    private static func validURL(_ value: String?) -> URL? {
        guard let url = value.flatMap(URL.init(string:)), ["https", "http"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }
    private static func normalizedGender(_ value: Int?) -> String? {
        switch value { case 1: "female"; case 2: "male"; default: nil }
    }
    private static func normalizedUnique(_ values: [String]) -> [String] { Array(Set(values.compactMap(normalizedName))).sorted() }
    private static func sanitizedList(_ values: [String]) -> [String] {
        Array(Set(values.compactMap { NeutralTextSanitizer.sanitize($0, policy: .omit) })).sorted()
    }
    private static func sanitizedComponents<Value>(_ values: [Value], components: (Value) -> [String?]) -> [String] {
        values.compactMap { value in
            let parts = components(value).compactMap { NeutralTextSanitizer.sanitize($0, policy: .omit) }
            return parts.isEmpty ? nil : parts.joined(separator: " — ")
        }
    }
}

nonisolated extension CatalogCreaturePayload {
    func domainValue() -> CreatureProfile {
        let summary = CreatureSummary(id: id, name: name, displayName: displayName, generation: generation, types: types, artworkURL: artworkURL)
        return CreatureProfile(
            summary: summary, genus: genus, description: description, heightMetres: heightMetres, weightKilograms: weightKilograms,
            baseExperience: baseExperience, captureRate: nil, baseHappiness: nil, growthRate: nil,
            abilities: abilities, hiddenAbilities: hiddenAbilities,
            stats: CreatureStats(hitPoints: stats.hitPoints, attack: stats.attack, defense: stats.defense, specialAttack: stats.specialAttack, specialDefense: stats.specialDefense, speed: stats.speed),
            forms: forms.map { $0.domainValue() },
            moves: moves.map { $0.domainSummary() },
            encounters: encounters.map { $0.domainValue() },
            versionGroups: versionGroups
        )
    }
}

nonisolated extension CatalogForm {
    func domainValue() -> CreatureForm {
        CreatureForm(id: id, name: name, displayName: displayName, isDefault: isDefault, types: types, artworkURL: artworkURL)
    }
}

nonisolated extension CatalogMove {
    func domainSummary() -> MoveSummary {
        MoveSummary(id: id, name: name, displayName: displayName, versionGroups: versionGroups, learningMethods: learningMethods)
    }

    func domainDetail() -> MoveDetail {
        MoveDetail(summary: domainSummary(), type: type, damageClass: damageClass, power: power, accuracy: accuracy, powerPoints: powerPoints, priority: priority, effect: effect)
    }
}

nonisolated extension CatalogEncounter {
    func domainValue() -> Encounter {
        Encounter(location: location, versionGroups: versionGroups, minimumLevel: minimumLevel, maximumLevel: maximumLevel, chancePercent: chancePercent)
    }
}

nonisolated extension CatalogEvolutionPayload {
    func domainValue() -> EvolutionChain {
        func map(_ node: CatalogEvolutionNode) -> EvolutionNode {
            EvolutionNode(creatureID: node.creatureID, name: node.name, requirements: node.requirements.map {
                EvolutionRequirement(trigger: $0.trigger, minimumLevel: $0.minimumLevel, item: $0.item, heldItem: $0.heldItem, tradeSpecies: $0.tradeSpecies, minimumHappiness: $0.minimumHappiness, minimumAffection: $0.minimumAffection, minimumBeauty: $0.minimumBeauty, timeOfDay: $0.timeOfDay, location: $0.location, weather: $0.weather, relativePhysicalStats: $0.relativePhysicalStats, gender: $0.gender, knownMove: $0.knownMove, knownMoveType: $0.knownMoveType, partySpecies: $0.partySpecies, partyType: $0.partyType, needsUpsideDownDevice: $0.needsUpsideDownDevice)
            }, children: node.children.map(map))
        }
        return EvolutionChain(id: id, root: map(root))
    }
}

nonisolated extension CatalogCardPayload {
    func domainValue() -> BattleCardDetail {
        let summary = BattleCardSummary(id: id, relatedCreatureIDs: relatedCreatureIDs, name: name, setID: setID, setName: setName, collectorNumber: collectorNumber, rarity: rarity, types: types, hitPoints: hitPoints, smallImageURL: smallImageURL, largeImageURL: largeImageURL)
        return BattleCardDetail(summary: summary, subtypes: subtypes, rules: rules, abilities: abilities, attacks: attacks, weaknesses: weaknesses, resistances: resistances, retreatCost: retreatCost, evolutionText: evolutionText, artist: artist, flavorText: flavorText, regulationMark: regulationMark, legalities: legalities)
    }
}
