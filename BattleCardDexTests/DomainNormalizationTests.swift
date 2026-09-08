import Foundation
import Testing
@testable import Battle_Card_Dex

@Suite("Domain and normalization")
struct DomainNormalizationTests {
    private struct Cases: Decodable {
        let creature: LoaderCreatureDTO
        let missingCreature: LoaderCreatureDTO
        let evolution: LoaderEvolutionChainDTO
        let form: LoaderFormDTO
        let move: LoaderMoveDetailDTO
        let encounters: [LoaderEncounterDTO]
        let card: LoaderBattleCardDTO
    }

    @Test func fixturesDecodeMissingNullExtraAndUnknownFields() throws {
        let cases = try fixtureCases()
        #expect(cases.creature.baseExperience == nil)
        #expect(cases.missingCreature.height == nil)
        #expect(cases.missingCreature.weight == nil)
        #expect(cases.missingCreature.abilities == nil)
        #expect(cases.card.rarity == nil)
        #expect(cases.card.artist == nil)
        #expect(cases.evolution.chain?.evolvesTo?.count == 2)

        let missing = try CatalogNormalizer.creature(from: cases.missingCreature)
        #expect(missing.heightMetres == nil)
        #expect(missing.weightKilograms == nil)
        #expect(missing.abilities.isEmpty)
        #expect(missing.moves.isEmpty)
    }

    @Test func creatureDTOMapsThroughCatalogToDomain() throws {
        let dto = try fixtureCases().creature
        let catalog = try CatalogNormalizer.creature(from: dto)
        let domain = catalog.domainValue()

        #expect(catalog.schemaVersion == 1)
        #expect(catalog.id == 25)
        #expect(catalog.name == "spark-mouse")
        #expect(catalog.displayName == "Spark Mouse")
        #expect(catalog.types == ["electric"])
        #expect(catalog.heightMetres == 0.4)
        #expect(catalog.weightKilograms == 6.0)
        #expect(catalog.baseExperience == nil)
        #expect(catalog.abilities == ["static-charge"])
        #expect(catalog.hiddenAbilities == ["lightning-rod"])
        #expect(catalog.stats.hitPoints == 35)
        #expect(catalog.stats.specialAttack == 50)
        #expect(catalog.moves.map(\.id) == [98])
        #expect(catalog.moves[0].versionGroups == ["red-blue", "yellow"])
        #expect(catalog.moves[0].learningMethods == ["level-up", "machine"])
        #expect(catalog.versionGroups == ["red-blue", "yellow"])
        #expect(domain.summary == CreatureSummary(id: 25, name: "spark-mouse", displayName: "Spark Mouse", generation: nil, types: ["electric"], artworkURL: nil))
        #expect(domain.heightMetres == 0.4)
        #expect(domain.stats.speed == 90)
        #expect(domain.moves.first?.displayName == "Quick Attack")
    }

    @Test func cardDTOMapsThroughCatalogToDomainAndDropsUnsupportedData() throws {
        let catalog = try CatalogNormalizer.card(from: fixtureCases().card)
        let domain = catalog.domainValue()

        #expect(catalog.relatedCreatureIDs == [25])
        #expect(catalog.types == ["electric"])
        #expect(catalog.hitPoints == 60)
        #expect(catalog.rarity == nil)
        #expect(catalog.smallImageURL?.scheme == "https")
        #expect(catalog.largeImageURL == nil)
        #expect(catalog.legalities == ["expanded": "Legal"])
        #expect(catalog.abilities == ["Charge — Ability — Stores energy."])
        #expect(catalog.attacks == ["Spark — Deals damage."])
        #expect(catalog.weaknesses == ["Fighting — ×2"])
        #expect(catalog.resistances == ["Metal — -30"])
        #expect(catalog.retreatCost == ["colorless"])
        #expect(catalog.evolutionText == "Small Mouse")
        #expect(domain.summary.collectorNumber == "001/100")
        #expect(domain.flavorText == "A neutral description.")
    }

    @Test func formMoveAndEncounterDTOsNormalizeToCatalogAndDomainShapes() throws {
        let cases = try fixtureCases()
        let form = try CatalogNormalizer.form(from: cases.form)
        let move = try CatalogNormalizer.move(
            from: cases.move,
            versionGroups: ["Yellow", "Red Blue", "yellow"],
            learningMethods: ["Level Up"]
        )
        let encounters = CatalogNormalizer.encounters(from: cases.encounters)

        #expect(form.id == 10025)
        #expect(form.name == "spark-mouse-costume")
        #expect(form.types == ["electric"])
        #expect(form.artworkURL?.scheme == "https")
        #expect(move.id == 98)
        #expect(move.type == "normal")
        #expect(move.damageClass == "physical")
        #expect(move.power == 40)
        #expect(move.accuracy == 100)
        #expect(move.powerPoints == 30)
        #expect(move.priority == 1)
        #expect(move.effect == "This move acts first.")
        #expect(move.versionGroups == ["red-blue", "yellow"])
        #expect(encounters == [CatalogEncounter(location: "forest-path", versionGroups: ["red-blue"], minimumLevel: 2, maximumLevel: 6, chancePercent: 30)])

        let domainMove = move.domainDetail()
        #expect(domainMove.effect == "This move acts first.")
        #expect(domainMove.summary.learningMethods == ["level-up"])
        #expect(form.domainValue().displayName == "Spark Mouse Costume")
        #expect(encounters[0].domainValue().minimumLevel == 2)
    }

    @Test func recursiveEvolutionMapsBranchesAndEveryCondition() throws {
        let catalog = try CatalogNormalizer.evolution(from: fixtureCases().evolution)
        let domain = catalog.domainValue()

        #expect(catalog.root.children.count == 2)
        #expect(domain.memberIDs == [1, 2, 3])
        let day = try #require(domain.root.children.first { $0.creatureID == 2 })
        let requirement = try #require(day.requirements.first)
        #expect(requirement.trigger == "level-up")
        #expect(requirement.minimumLevel == 20)
        #expect(requirement.item == "sun-stone")
        #expect(requirement.heldItem == "bright-charm")
        #expect(requirement.tradeSpecies == "trade-friend")
        #expect(requirement.minimumHappiness == 160)
        #expect(requirement.minimumAffection == 2)
        #expect(requirement.minimumBeauty == 170)
        #expect(requirement.timeOfDay == "day")
        #expect(requirement.location == "moss-rock")
        #expect(requirement.weather == "rain")
        #expect(requirement.relativePhysicalStats == 1)
        #expect(requirement.gender == "female")
        #expect(requirement.knownMove == "ancient-song")
        #expect(requirement.knownMoveType == "fairy")
        #expect(requirement.partySpecies == "companion")
        #expect(requirement.partyType == "dark")
        #expect(requirement.needsUpsideDownDevice)

        let night = try #require(domain.root.children.first { $0.creatureID == 3 })
        #expect(night.requirements.first?.trigger == "trade")
        #expect(night.requirements.first?.gender == "male")
        #expect(night.requirements.first?.minimumLevel == nil)
    }

    @Test func noEvolutionAndMultipleRequirementAlternativesRemainStable() throws {
        let noEvolutionJSON = Data(#"{"id":11,"chain":{"species":{"name":"solo","url":"https://example.invalid/species/6/"},"evolution_details":null,"evolves_to":[]}}"#.utf8)
        let noEvolutionDTO = try JSONDecoder().decode(LoaderEvolutionChainDTO.self, from: noEvolutionJSON)
        let noEvolution = try CatalogNormalizer.evolution(from: noEvolutionDTO).domainValue()
        #expect(noEvolution.root.children.isEmpty)
        #expect(noEvolution.memberIDs == [6])

        let alternativesJSON = Data(#"{"id":12,"chain":{"species":{"name":"root","url":"https://example.invalid/species/7/"},"evolves_to":[{"species":{"name":"result","url":"https://example.invalid/species/8/"},"evolution_details":[{"trigger":{"name":"level-up"},"min_level":20},{"trigger":{"name":"use-item"},"item":{"name":"moon-stone"}}],"evolves_to":[]}]}}"#.utf8)
        let alternativesDTO = try JSONDecoder().decode(LoaderEvolutionChainDTO.self, from: alternativesJSON)
        let alternatives = try CatalogNormalizer.evolution(from: alternativesDTO).domainValue()
        #expect(alternatives.root.children[0].requirements.count == 2)
        #expect(alternatives.root.children[0].requirements[0].minimumLevel == 20)
        #expect(alternatives.root.children[0].requirements[1].item == "moon-stone")
    }

    @Test func sanitizerHandlesCaseAccentsPunctuationAndEmbeddedPhrases() {
        let plain = restrictedVariant(accented: false, punctuation: false)
        let accented = restrictedVariant(accented: true, punctuation: false)
        let punctuated = restrictedVariant(accented: false, punctuation: true)
        let embedded = "prefix\(plain)suffix"

        for value in [plain.uppercased(), accented, punctuated, embedded] {
            #expect(NeutralTextSanitizer.containsRestrictedBrand(in: value))
            #expect(NeutralTextSanitizer.sanitize(value, policy: .omit) == nil)
            #expect(NeutralTextSanitizer.sanitize(value, policy: .rewriteAsCreature) == "Creature")
        }
        #expect(NeutralTextSanitizer.sanitize("  Neutral factual text.  ", policy: .omit) == "Neutral factual text.")
        #expect(!NeutralTextSanitizer.containsRestrictedBrand(in: "neutral creature"))
    }

    @Test func unsafeDescriptionsCannotEnterCatalogAndRequiredUnsafeTextFails() throws {
        let unsafe = restrictedVariant(accented: true, punctuation: true)
        let rawCard = LoaderBattleCardDTO(
            id: "safe-id", name: "Safe Card", nationalIndexNumbers: [1],
            set: .init(id: "safe-set", name: "Safe Set"), number: "1", rarity: nil,
            types: [], hp: nil, images: nil, subtypes: [], rules: [unsafe], artist: nil,
            flavorText: "Before \(unsafe) after", regulationMark: nil, legalities: ["standard": unsafe],
            abilities: nil, attacks: nil, weaknesses: nil, resistances: nil, retreatCost: nil, evolvesFrom: nil
        )
        let catalog = try CatalogNormalizer.card(from: rawCard)
        #expect(catalog.rules.isEmpty)
        #expect(catalog.flavorText == nil)
        #expect(catalog.legalities.isEmpty)

        let unsafeName = LoaderBattleCardDTO(
            id: "safe-id", name: unsafe, nationalIndexNumbers: [1],
            set: .init(id: "safe-set", name: "Safe Set"), number: "1", rarity: nil,
            types: [], hp: nil, images: nil, subtypes: [], rules: [], artist: nil,
            flavorText: nil, regulationMark: nil, legalities: nil,
            abilities: nil, attacks: nil, weaknesses: nil, resistances: nil, retreatCost: nil, evolvesFrom: nil
        )
        #expect(throws: CatalogMappingError.unsafeRequiredText("card.name")) {
            try CatalogNormalizer.card(from: unsafeName)
        }
    }

    @Test func onlyNormalizedEnvelopesAreAcceptedForPersistence() throws {
        let dto = try fixtureCases().creature
        let raw = try JSONEncoder().encode(RawEncodableCreature(dto))
        #expect(throws: CatalogEnvelopeError.rawPayloadRejected) {
            try CatalogPersistenceEnvelope.validatingPersistedBytes(raw)
        }

        let catalog = try CatalogNormalizer.creature(from: dto)
        let envelope = try CatalogPersistenceEnvelope(catalog)
        let document = try CatalogDocument(identifier: "creature-0025", envelope: envelope, contentHash: "fixture-hash")
        #expect(try document.persistedEnvelope().decode(CatalogCreaturePayload.self) == catalog)
        #expect(throws: CatalogEnvelopeError.kindMismatch) {
            try document.persistedEnvelope().decode(CatalogCardPayload.self)
        }

        #expect(throws: CatalogEnvelopeError.unsafeText) {
            try CatalogPersistenceEnvelope(UnsafeNormalizedPayload(
                schemaVersion: 1,
                text: "embedded-\(restrictedVariant(accented: true, punctuation: true))-phrase"
            ))
        }
    }

    @Test func transportURLsDoNotFailVisibleTextSanitization() throws {
        let restricted = restrictedVariant(accented: false, punctuation: false)
        let payload = CatalogCreaturePayload(
            schemaVersion: 1,
            id: 1,
            name: "seed-creature",
            displayName: "Seed Creature",
            generation: "generation-1",
            types: ["leaf"],
            artworkURL: URL(string: "https://cdn.example.invalid/\(restricted)/1.png"),
            genus: nil,
            description: nil,
            heightMetres: nil,
            weightKilograms: nil,
            baseExperience: nil,
            abilities: [],
            hiddenAbilities: [],
            stats: .init(hitPoints: 1, attack: 1, defense: 1, specialAttack: 1, specialDefense: 1, speed: 1),
            forms: [],
            moves: [],
            encounters: [],
            versionGroups: []
        )

        let envelope = try CatalogPersistenceEnvelope(payload)
        #expect(try envelope.decode(CatalogCreaturePayload.self) == payload)
    }

    @Test func malformedRequiredIDsAreRejected() throws {
        let missingID = Data(#"{"name":"missing-id"}"#.utf8)
        let dto = try JSONDecoder().decode(LoaderCreatureDTO.self, from: missingID)
        #expect(throws: CatalogMappingError.invalidIdentifier("creature.id")) {
            try CatalogNormalizer.creature(from: dto)
        }
    }

    private func fixtureCases() throws -> Cases {
        try JSONDecoder().decode(Cases.self, from: DeterministicFixtures.data(named: "normalization-cases"))
    }

    private func restrictedVariant(accented: Bool, punctuation: Bool) -> String {
        let scalars = accented
            ? [112, 111, 107, 233, 109, 111, 110]
            : [112, 111, 107, 101, 109, 111, 110]
        let letters = scalars.compactMap(UnicodeScalar.init).map(String.init)
        return punctuation ? letters.joined(separator: "-") : letters.joined()
    }
}

/// A test-only encoding shim demonstrates that provider bytes are rejected even
/// when they happen to contain otherwise valid source values.
private struct RawEncodableCreature: Encodable {
    let id: Int?
    let name: String?
    let height: Int?
    let weight: Int?

    init(_ dto: LoaderCreatureDTO) {
        id = dto.id
        name = dto.name
        height = dto.height
        weight = dto.weight
    }
}

private struct UnsafeNormalizedPayload: NormalizedCatalogPayload {
    static let kind = CatalogPayloadKind.card
    let schemaVersion: Int
    let text: String
}
