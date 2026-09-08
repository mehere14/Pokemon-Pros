import Foundation
import Combine
import OSLog
import SwiftUI

@MainActor
final class CatalogViewModel: ObservableObject {
    private nonisolated static let logger = Logger(
        subsystem: "com.askcruit.Battle-Card-Dex",
        category: "CatalogViewModel"
    )
    enum State: Equatable {
        case loading
        case ready
        case stale
        case emptyInstall
        case offline
        case incompatibleSchema
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var creatures: [CreatureSummary] = []
    @Published private(set) var profiles: [Int: CreatureProfile] = [:]
    @Published private(set) var evolutions: [Int: EvolutionChain] = [:]
    @Published private(set) var cards: [BattleCardDetail] = []

    private let coordinator: CatalogCoordinator?
    private let supportedRange: ClosedRange<Int>
    private let manifestRecordIdentifier: String
    private let automaticallyWarmDetails: Bool
    private var loadedDocuments: [String: CatalogDocument] = [:]
    private var detailWarmupTask: Task<Void, Never>?
    let imageRepository: (any ImageRepository)?

    init(coordinator: CatalogCoordinator? = nil,
         supportedRange: ClosedRange<Int> = 1...30,
         manifestRecordIdentifier: String = "catalog-manifest-v1",
         automaticallyWarmDetails: Bool = true,
         imageRepository: (any ImageRepository)? = nil) {
        self.coordinator = coordinator
        self.supportedRange = supportedRange
        self.manifestRecordIdentifier = manifestRecordIdentifier
        self.automaticallyWarmDetails = automaticallyWarmDetails
        self.imageRepository = imageRepository
    }

    static func preview() -> CatalogViewModel {
        let model = CatalogViewModel()
        model.creatures = (1...6).map { id in
            CreatureSummary(id: id, name: "creature-\(id)", displayName: "Creature \(id)", generation: "generation-1", types: [id.isMultiple(of: 2) ? "water" : "leaf"], artworkURL: nil)
        }
        model.cards = (1...4).map { id in
            BattleCardDetail(
                summary: BattleCardSummary(
                    id: "preview-card-\(id)",
                    relatedCreatureIDs: [1],
                    name: "Creature 1 Card \(id)",
                    setID: "preview-set",
                    setName: "Preview Set",
                    collectorNumber: String(id),
                    rarity: "Rare",
                    types: ["leaf"],
                    hitPoints: 100 + id * 10,
                    smallImageURL: nil,
                    largeImageURL: nil
                ),
                subtypes: [], rules: [], abilities: [], attacks: [], weaknesses: [],
                resistances: [], retreatCost: [], evolutionText: nil, artist: nil,
                flavorText: nil, regulationMark: nil, legalities: [:]
            )
        }
        model.state = .ready
        return model
    }

    func load() async {
        await load(forceRefresh: false)
    }

    func retry() async {
        await load(forceRefresh: true)
    }

    func loadDetails(for creatureIDs: [Int]) async {
        guard let coordinator else { return }
        let identifiers = Array(Set(creatureIDs)).flatMap { id -> [String] in
            guard let document = loadedDocuments["catalog-creature-\(id)"],
                  let envelope = try? document.persistedEnvelope(),
                  let creature = try? envelope.decode(CatalogCreaturePayload.self) else { return [] }
            return (creature.cardRecordIdentifiers ?? []) + [creature.evolutionRecordIdentifier].compactMap { $0 }
        }
        let missingIdentifiers = Array(Set(identifiers)).filter { loadedDocuments[$0] == nil }.sorted()
        guard !missingIdentifiers.isEmpty else { return }
        let snapshot = await coordinator.load(identifiers: missingIdentifiers)
        for document in snapshot.documents { loadedDocuments[document.identifier] = document }
        mergeDetails(from: snapshot.documents)
    }

    private func scheduleDetailWarmup() {
        guard automaticallyWarmDetails, detailWarmupTask == nil else { return }
        let ids = creatures.map(\.id)
        detailWarmupTask = Task(priority: .utility) { [weak self] in
            // Give SwiftUI a chance to present the catalog before background I/O
            // and decoding begins.
            try? await Task.sleep(nanoseconds: 350_000_000)
            for start in stride(from: 0, to: ids.count, by: 25) {
                guard !Task.isCancelled, let self else { return }
                let end = min(start + 25, ids.count)
                await self.loadDetails(for: Array(ids[start..<end]))
                await Task.yield()
            }
            self?.detailWarmupTask = nil
        }
    }

    private func load(forceRefresh: Bool) async {
        guard let coordinator else { state = creatures.isEmpty ? .emptyInstall : .ready; return }
        state = .loading
        let primaryIdentifiers = [manifestRecordIdentifier] + supportedRange.map { "catalog-creature-\($0)" }
        let fetch: ([String]) async -> CatalogCoordinatorSnapshot = { ids in
            await coordinator.load(identifiers: ids)
        }
        let primarySnapshot = await fetch(primaryIdentifiers)
        Self.logger.info("Primary load completed with state \(String(describing: primarySnapshot.state), privacy: .public), \(primarySnapshot.documents.count, privacy: .public) records, and \(primarySnapshot.failedIdentifiers.count, privacy: .public) misses")
#if DEBUG
        print("BattleCardDex catalog: primary load state=\(primarySnapshot.state) records=\(primarySnapshot.documents.count) misses=\(primarySnapshot.failedIdentifiers.count)")
#endif
        guard let manifest = Self.manifest(in: primarySnapshot.documents, identifier: manifestRecordIdentifier) else {
            Self.logger.error("The catalog manifest could not be found or decoded")
#if DEBUG
            print("BattleCardDex catalog: manifest missing or undecodable")
#endif
            apply(documents: primarySnapshot.documents, state: primarySnapshot.state)
            return
        }

        let additionalCreatureIdentifiers = manifest.creatureCount > supportedRange.upperBound
            ? ((supportedRange.upperBound + 1)...manifest.creatureCount).map { "catalog-creature-\($0)" }
            : []
        let relatedIdentifiers = additionalCreatureIdentifiers
        let relatedSnapshot: CatalogCoordinatorSnapshot = relatedIdentifiers.isEmpty
            ? CatalogCoordinatorSnapshot(state: .ready, documents: [], failedIdentifiers: [], servedFromCache: primarySnapshot.servedFromCache)
            : await fetch(relatedIdentifiers)
        let cardSnapshot = CatalogCoordinatorSnapshot(state: .ready, documents: [], failedIdentifiers: [], servedFromCache: true)
        Self.logger.info("Related load completed with state \(String(describing: relatedSnapshot.state), privacy: .public), \(relatedSnapshot.documents.count, privacy: .public) records, and \(relatedSnapshot.failedIdentifiers.count, privacy: .public) misses")
#if DEBUG
        print("BattleCardDex catalog: related load state=\(relatedSnapshot.state) records=\(relatedSnapshot.documents.count) misses=\(relatedSnapshot.failedIdentifiers.count)")
#endif
        var snapshot = Self.combined(primarySnapshot, relatedSnapshot, cardSnapshot)
        var allDocuments = Self.mergedDocuments([primarySnapshot.documents, relatedSnapshot.documents, cardSnapshot.documents])
        loadedDocuments = Dictionary(uniqueKeysWithValues: allDocuments.map { ($0.identifier, $0) })
        apply(documents: allDocuments, state: snapshot.state)
        scheduleDetailWarmup()

        // A warm launch has now rendered from memory/SwiftData. Refresh only the
        // manifest, then ask CloudKit for records whose published hashes changed.
        // This preserves the fixed read order while avoiding a full-catalog fetch
        // on every launch.
        guard forceRefresh || primarySnapshot.servedFromCache || relatedSnapshot.servedFromCache else { return }
        let refreshedManifestSnapshot = await coordinator.refresh(identifiers: [manifestRecordIdentifier])
        guard let refreshedManifest = Self.manifest(in: refreshedManifestSnapshot.documents, identifier: manifestRecordIdentifier) else {
            if refreshedManifestSnapshot.state != .ready {
                snapshot = Self.combined(snapshot, refreshedManifestSnapshot)
                apply(documents: allDocuments, state: snapshot.state)
            }
            return
        }

        let currentByIdentifier = Dictionary(uniqueKeysWithValues: allDocuments.map { ($0.identifier, $0) })
        var changedIdentifiers = refreshedManifest.contentHashes.keys.filter { identifier in
            guard identifier.hasPrefix("catalog-creature-") else { return false }
            return currentByIdentifier[identifier]?.contentHash != refreshedManifest.contentHashes[identifier]
        }.sorted()
        if refreshedManifest.creatureCount > manifest.creatureCount {
            changedIdentifiers.append(contentsOf: ((manifest.creatureCount + 1)...refreshedManifest.creatureCount).map {
                "catalog-creature-\($0)"
            })
        }
        let changedSnapshot = changedIdentifiers.isEmpty
            ? CatalogCoordinatorSnapshot(state: .ready, documents: [], failedIdentifiers: [])
            : await coordinator.refresh(identifiers: changedIdentifiers)
        let refreshedCards = CatalogCoordinatorSnapshot(state: .ready, documents: [], failedIdentifiers: [], servedFromCache: true)
        snapshot = Self.combined(snapshot, refreshedManifestSnapshot, changedSnapshot, refreshedCards)

        let expectedIdentifiers = Set((1...max(refreshedManifest.creatureCount, supportedRange.upperBound)).map { "catalog-creature-\($0)" })
            .union([manifestRecordIdentifier])
        var refreshedDocuments = Dictionary(uniqueKeysWithValues: allDocuments.map { ($0.identifier, $0) })
        for document in refreshedManifestSnapshot.documents + changedSnapshot.documents + refreshedCards.documents {
            refreshedDocuments[document.identifier] = document
        }
        allDocuments = refreshedDocuments.values
            .filter { expectedIdentifiers.contains($0.identifier) }
            .sorted { $0.identifier < $1.identifier }
        loadedDocuments = Dictionary(uniqueKeysWithValues: allDocuments.map { ($0.identifier, $0) })
        apply(documents: allDocuments, state: snapshot.state)
    }

    private func apply(documents: [CatalogDocument], state coordinatorState: CatalogCoordinatorState) {
        var summaries: [CreatureSummary] = []
        var loadedProfiles: [Int: CreatureProfile] = [:]
        var loadedEvolutions: [Int: EvolutionChain] = [:]
        var loadedCards: [BattleCardDetail] = []
        for document in documents {
            guard let envelope = try? document.persistedEnvelope() else { continue }
            switch envelope.kind {
            case .creature:
                guard let value = try? envelope.decode(CatalogCreaturePayload.self) else { continue }
                let profile = value.domainValue()
                summaries.append(profile.summary)
                loadedProfiles[profile.summary.id] = profile
            case .evolution:
                if let value = try? envelope.decode(CatalogEvolutionPayload.self) { loadedEvolutions[value.id] = value.domainValue() }
            case .card:
                if let value = try? envelope.decode(CatalogCardPayload.self) { loadedCards.append(value.domainValue()) }
            case .manifest: break
            }
        }
        creatures = summaries.sorted { $0.id < $1.id }
        profiles = loadedProfiles
        evolutions = loadedEvolutions
        cards = loadedCards.sorted { $0.id < $1.id }
        switch coordinatorState {
        case .ready: state = .ready
        case .stale: state = .stale
        case .emptyInstall: state = .emptyInstall
        case .offline: state = .offline
        case .incompatibleSchema: state = .incompatibleSchema
        default: state = creatures.isEmpty ? .emptyInstall : .ready
        }
    }

    private func mergeDetails(from documents: [CatalogDocument]) {
        var updatedEvolutions = evolutions
        var updatedCards = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        for document in documents {
            guard let envelope = try? document.persistedEnvelope() else { continue }
            switch envelope.kind {
            case .evolution:
                if let value = try? envelope.decode(CatalogEvolutionPayload.self) {
                    updatedEvolutions[value.id] = value.domainValue()
                }
            case .card:
                if let value = try? envelope.decode(CatalogCardPayload.self) {
                    let card = value.domainValue()
                    updatedCards[card.id] = card
                }
            case .creature, .manifest:
                break
            }
        }
        evolutions = updatedEvolutions
        cards = updatedCards.values.sorted { $0.id < $1.id }
    }

    private static func manifest(in documents: [CatalogDocument], identifier: String) -> CatalogManifestPayload? {
        guard let document = documents.first(where: { $0.identifier == identifier }) else { return nil }
        return try? document.persistedEnvelope().decode(CatalogManifestPayload.self)
    }

    private static func mergedDocuments(_ groups: [[CatalogDocument]]) -> [CatalogDocument] {
        Dictionary(groups.flatMap { $0 }.map { ($0.identifier, $0) }, uniquingKeysWith: { _, latest in latest })
            .values.sorted { $0.identifier < $1.identifier }
    }

    private static func combined(_ snapshots: CatalogCoordinatorSnapshot...) -> CatalogCoordinatorSnapshot {
        let documents = mergedDocuments(snapshots.map(\.documents))
        let failed = Array(Set(snapshots.flatMap(\.failedIdentifiers))).sorted()
        let hasDocuments = !documents.isEmpty
        let states = snapshots.map(\.state)
        let state: CatalogCoordinatorState
        if states.contains(.incompatibleSchema) {
            state = .incompatibleSchema
        } else if !hasDocuments, states.contains(.offline) {
            state = .offline
        } else if !hasDocuments, states.contains(.emptyInstall) {
            state = .emptyInstall
        } else if !failed.isEmpty || states.contains(.stale) || states.contains(.offline) {
            state = .stale
        } else {
            state = .ready
        }
        return CatalogCoordinatorSnapshot(
            state: state,
            documents: documents,
            failedIdentifiers: failed,
            servedFromCache: snapshots.allSatisfy(\.servedFromCache)
        )
    }

    func profile(for id: Int) -> CreatureProfile? { profiles[id] }

    func cards(for creatureID: Int) -> [BattleCardDetail] {
        cards.filter { $0.summary.relatedCreatureIDs.contains(creatureID) }
    }
}
