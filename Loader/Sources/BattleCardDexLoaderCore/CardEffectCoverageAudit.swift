import Foundation

public enum CardFinish: String, Codable, CaseIterable, Sendable { case normal, holo, reverseHolo, firstEditionNormal, firstEditionHolo, metal, lenticular, unknown }
public enum CardEffectFamily: String, Codable, CaseIterable, Sendable {
    case basic, reverseHolo, regularHolo, cosmosHolo, amazingRare, radiantHolo, trainerGalleryHolo
    case v, vFullArt, vAlternateArt, vmax, vmaxRainbow, vstar, trainerFullArt, rainbowRare
    case secretGold, trainerGalleryV, shinyVault, unsupported
}
public enum CardMaskPreset: String, Codable, CaseIterable, Sendable { case specularSpot, artworkWindow, outsideArtworkWindow, fullCard, fullArt, radiantBurst, amazingBreakout, customOverride }
public enum AuditConfidence: String, Codable, CaseIterable, Sendable { case exact, inferred, ambiguous, unsupported, unmatched }

public struct ProviderEffectCard: Codable, Equatable, Sendable {
    public let id: String; public let name: String; public let setID: String; public let number: String
    public let rarity: String?; public let subtypes: [String]; public let finishes: Set<CardFinish>
    public init(id: String, name: String, setID: String, number: String, rarity: String?, subtypes: [String], finishes: Set<CardFinish>) {
        self.id = id; self.name = name; self.setID = setID; self.number = number; self.rarity = rarity; self.subtypes = subtypes; self.finishes = finishes
    }
}

public struct TCGdexEffectCard: Codable, Equatable, Sendable {
    public let id: String; public let name: String; public let localID: String; public let setID: String
    public let rarity: String?; public let category: String?; public let stage: String?; public let suffix: String?
    public let finishes: Set<CardFinish>; public let foilPattern: String?
    public init(id: String, name: String, localID: String, setID: String, rarity: String?, category: String?, stage: String?, suffix: String?, finishes: Set<CardFinish>, foilPattern: String? = nil) {
        self.id = id; self.name = name; self.localID = localID; self.setID = setID; self.rarity = rarity; self.category = category; self.stage = stage; self.suffix = suffix; self.finishes = finishes; self.foilPattern = foilPattern
    }
}

public struct CardEffectAuditEntry: Codable, Equatable, Sendable {
    public let id: String; public let name: String; public let setID: String; public let number: String
    public let finishes: [CardFinish]; public let family: CardEffectFamily; public let mask: CardMaskPreset
    public let confidence: AuditConfidence; public let sources: [String]; public let foilPattern: String?; public let note: String?
}

public struct CardEffectCoverageReport: Codable, Equatable, Sendable {
    public let generatedAt: Date; public let range: String; public let entries: [CardEffectAuditEntry]
    public var counts: [String: Int] {
        var result = ["cards": entries.count]
        for confidence in AuditConfidence.allCases { result[confidence.rawValue] = entries.count { $0.confidence == confidence } }
        for family in CardEffectFamily.allCases { result["family_\(family.rawValue)"] = entries.count { $0.family == family } }
        return result
    }
}

public struct CardEffectCoverageEngine: Sendable {
    private static let familyOverrides: [String: CardEffectFamily] = [
        "swsh7-167": .vAlternateArt
    ]
    public init() {}

    public func classify(_ card: ProviderEffectCard, enriched: TCGdexEffectCard?) -> CardEffectAuditEntry {
        guard let enriched else { return entry(card, finishes: card.finishes, family: inferredFamily(card.rarity, card.subtypes), confidence: .unmatched, sources: ["card-provider"], foil: nil, note: "No TCGdex match") }
        let identityMatches = normalized(card.name) == normalized(enriched.name)
            && normalized(card.setID) == normalized(enriched.setID)
            && normalized(card.number) == normalized(enriched.localID)
        guard card.id == enriched.id || identityMatches else {
            return entry(card, finishes: card.finishes, family: .unsupported, confidence: .ambiguous, sources: ["card-provider", "tcgdex"], foil: enriched.foilPattern, note: "Candidate identity conflict")
        }
        let finishes = card.finishes.union(enriched.finishes)
        let family = Self.familyOverrides[card.id] ?? family(rarity: enriched.rarity ?? card.rarity, subtypes: card.subtypes, stage: enriched.stage, suffix: enriched.suffix, foil: enriched.foilPattern, finishes: finishes)
        let explicit = !enriched.finishes.isEmpty || enriched.foilPattern != nil
        let confidence: AuditConfidence = family == .unsupported ? .unsupported : (explicit ? .exact : .inferred)
        return entry(card, finishes: finishes, family: family, confidence: confidence, sources: ["card-provider", "tcgdex"], foil: enriched.foilPattern, note: nil)
    }

    private func family(rarity: String?, subtypes: [String], stage: String?, suffix: String?, foil: String?, finishes: Set<CardFinish>) -> CardEffectFamily {
        let value = ([rarity, stage, suffix].compactMap { $0 } + subtypes).joined(separator: " ").lowercased()
        let foil = foil?.lowercased() ?? ""
        if foil.contains("cosmos") || foil.contains("galaxy") { return .cosmosHolo }
        if value.contains("amazing") { return .amazingRare }
        if value.contains("radiant") { return .radiantHolo }
        if value.contains("shiny") { return .shinyVault }
        if value.contains("trainer gallery") && value.contains("v") { return .trainerGalleryV }
        if value.contains("trainer gallery") { return .trainerGalleryHolo }
        if value.contains("secret") && (value.contains("gold") || foil.contains("gold")) { return .secretGold }
        if value.contains("rainbow") && value.contains("vmax") { return .vmaxRainbow }
        if value.contains("rainbow") { return .rainbowRare }
        if value.contains("alternate") && value.contains("v") { return .vAlternateArt }
        if value.contains("full art") && value.contains("trainer") { return .trainerFullArt }
        if value.contains("full art") && value.contains("v") { return .vFullArt }
        if value.contains("vmax") { return .vmax }
        if value.contains("vstar") { return .vstar }
        if suffix?.lowercased() == "v" || value.hasSuffix(" v") { return .v }
        if finishes.contains(.reverseHolo) { return .reverseHolo }
        if finishes.contains(.holo) || finishes.contains(.firstEditionHolo) { return .regularHolo }
        if finishes.contains(.normal) || value.contains("common") || value.contains("uncommon") { return .basic }
        return .unsupported
    }

    private func inferredFamily(_ rarity: String?, _ subtypes: [String]) -> CardEffectFamily {
        let value = ([rarity].compactMap { $0 } + subtypes).joined(separator: " ").lowercased()
        if value.contains("amazing") { return .amazingRare }
        if value.contains("radiant") { return .radiantHolo }
        if value.contains("shiny") { return .shinyVault }
        if value.contains("rainbow") { return .rainbowRare }
        if value.contains("holo") { return .regularHolo }
        if value.contains("common") || value.contains("uncommon") { return .basic }
        return .unsupported
    }

    private func entry(_ card: ProviderEffectCard, finishes: Set<CardFinish>, family: CardEffectFamily, confidence: AuditConfidence, sources: [String], foil: String?, note: String?) -> CardEffectAuditEntry {
        CardEffectAuditEntry(id: card.id, name: card.name, setID: card.setID, number: card.number,
            finishes: finishes.isEmpty ? [.unknown] : finishes.sorted { $0.rawValue < $1.rawValue }, family: family,
            mask: Self.mask(for: family), confidence: confidence, sources: sources, foilPattern: foil, note: note)
    }

    public static func mask(for family: CardEffectFamily) -> CardMaskPreset {
        switch family {
        case .basic: .specularSpot
        case .reverseHolo: .outsideArtworkWindow
        case .regularHolo, .cosmosHolo: .artworkWindow
        case .amazingRare: .amazingBreakout
        case .radiantHolo: .radiantBurst
        case .vFullArt, .vAlternateArt, .vmaxRainbow, .trainerFullArt, .rainbowRare, .secretGold, .trainerGalleryV, .shinyVault: .fullArt
        case .v, .vmax, .vstar, .trainerGalleryHolo: .fullCard
        case .unsupported: .specularSpot
        }
    }

    private func normalized(_ value: String) -> String { String(value.lowercased().filter { $0.isLetter || $0.isNumber }) }
}

public struct CardEffectCoverageAudit: Sendable {
    private let transport: any LoaderTransport; private let cardAPIKey: String?
    public init(transport: any LoaderTransport, cardAPIKey: String? = nil) { self.transport = transport; self.cardAPIKey = cardAPIKey }

    public func run(range: IndexRange) async throws -> CardEffectCoverageReport {
        var cards: [String: ProviderEffectCard] = [:]
        for index in range.lowerBound...range.upperBound {
            var page = 1
            while true {
                var parts = URLComponents(string: "https://api.pokemontcg.io/v2/cards")!
                parts.queryItems = [.init(name: "q", value: "nationalPokedexNumbers:\(index)"), .init(name: "page", value: "\(page)"), .init(name: "pageSize", value: "250")]
                var headers: [String: String] = [:]; if let cardAPIKey { headers["X-Api-Key"] = cardAPIKey }
                let response = try await transport.send(.init(url: parts.url!, headers: headers))
                guard (200..<300).contains(response.statusCode) else { throw LoaderHTTPError.httpStatus(response.statusCode, retryAfter: nil) }
                let decoded = try JSONDecoder().decode(ProviderPage.self, from: response.body)
                for source in decoded.data ?? [] { if let card = source.auditValue { cards[card.id] = card } }
                guard (decoded.data?.count ?? 0) == 250 else { break }; page += 1
            }
        }
        let engine = CardEffectCoverageEngine()
        var entries: [CardEffectAuditEntry] = []
        for card in cards.values.sorted(by: { $0.id < $1.id }) {
            let url = URL(string: "https://api.tcgdex.net/v2/en/cards/\(card.id)")!
            let response = try await transport.send(.init(url: url))
            let enriched = (200..<300).contains(response.statusCode) ? try? JSONDecoder().decode(TCGdexCard.self, from: response.body).auditValue : nil
            entries.append(engine.classify(card, enriched: enriched))
        }
        return CardEffectCoverageReport(generatedAt: Date(), range: range.description, entries: entries)
    }
}

public enum CardEffectCoverageReportWriter {
    public static func write(_ report: CardEffectCoverageReport, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: directory.appendingPathComponent("card-effect-coverage.json"), options: .atomic)
        var markdown = "# Card Effect Coverage\n\nRange: \(report.range)  \nCards: \(report.entries.count)\n\n| Family | Exact | Inferred | Ambiguous | Unsupported | Unmatched | Sample | Rule |\n|---|---:|---:|---:|---:|---:|---|---|\n"
        for family in CardEffectFamily.allCases {
            let items = report.entries.filter { $0.family == family }
            guard !items.isEmpty else { continue }
            func count(_ confidence: AuditConfidence) -> Int { items.count { $0.confidence == confidence } }
            let sample = items.first.map { "\($0.name) (\($0.id))" } ?? "—"
            markdown += "| \(family.rawValue) | \(count(.exact)) | \(count(.inferred)) | \(count(.ambiguous)) | \(count(.unsupported)) | \(count(.unmatched)) | \(sample) | \(CardEffectCoverageEngine.mask(for: family).rawValue) |\n"
        }
        try markdown.write(to: directory.appendingPathComponent("card-effect-coverage.md"), atomically: true, encoding: .utf8)
    }
}

private struct ProviderPage: Decodable { let data: [ProviderCard]? }
private struct ProviderCard: Decodable {
    struct SetValue: Decodable { let id: String? }; struct PriceValue: Decodable { let low, mid, high, market, directLow: Double? }
    struct Market: Decodable { let prices: [String: PriceValue]? }
    let id, name, number, rarity: String?; let set: SetValue?; let subtypes: [String]?; let tcgplayer: Market?
    var auditValue: ProviderEffectCard? {
        guard let id, let name, let number, let setID = set?.id else { return nil }
        let mapped = Set((tcgplayer?.prices ?? [:]).keys.compactMap { key -> CardFinish? in
            switch key.lowercased() { case "normal": .normal; case "holofoil": .holo; case "reverseholofoil": .reverseHolo; case "1steditionholofoil": .firstEditionHolo; case "1steditionnormal": .firstEditionNormal; default: nil }
        })
        return ProviderEffectCard(id: id, name: name, setID: setID, number: number, rarity: rarity, subtypes: subtypes ?? [], finishes: mapped)
    }
}
private struct TCGdexCard: Decodable {
    struct SetValue: Decodable { let id: String }; struct Variants: Decodable { let normal, reverse, holo, firstEdition: Bool? }
    let id, name, localId, rarity, category, stage, suffix: String?; let set: SetValue; let variants: Variants?
    var auditValue: TCGdexEffectCard? {
        guard let id, let name, let localId else { return nil }; var finishes = Set<CardFinish>()
        if variants?.normal == true { finishes.insert(.normal) }; if variants?.reverse == true { finishes.insert(.reverseHolo) }
        if variants?.holo == true { finishes.insert(.holo) }; if variants?.firstEdition == true { finishes.insert(.firstEditionNormal) }
        return TCGdexEffectCard(id: id, name: name, localID: localId, setID: set.id, rarity: rarity, category: category, stage: stage, suffix: suffix, finishes: finishes)
    }
}
