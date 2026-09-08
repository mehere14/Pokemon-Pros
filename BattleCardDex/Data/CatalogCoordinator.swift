import Foundation
import OSLog

nonisolated enum CatalogCoordinatorState: Equatable, Sendable {
    case loading
    case ready
    case stale
    case refreshing
    case emptyInstall
    case offline
    case incompatibleSchema
}

nonisolated struct CatalogCoordinatorSnapshot: Equatable, Sendable {
    let state: CatalogCoordinatorState
    let documents: [CatalogDocument]
    let failedIdentifiers: [String]
    /// True when this response was entirely resolved from the process cache or
    /// local SwiftData mirror. Consumers use this to schedule a manifest-only
    /// public refresh after they have rendered the cached result.
    let servedFromCache: Bool

    init(
        state: CatalogCoordinatorState,
        documents: [CatalogDocument],
        failedIdentifiers: [String],
        servedFromCache: Bool = false
    ) {
        self.state = state
        self.documents = documents
        self.failedIdentifiers = failedIdentifiers
        self.servedFromCache = servedFromCache
    }
}

/// Fixed read order: memory, local SwiftData, then public CloudKit. Successful
/// public batches are retained in both memory and the local mirror.
actor CatalogCoordinator {
    private nonisolated static let logger = Logger(
        subsystem: "com.askcruit.Battle-Card-Dex",
        category: "CatalogCoordinator"
    )
    private let local: any LocalCatalogStore
    private let publicStore: any PublicCatalogStore
    private var memory: [String: CatalogDocument] = [:]
    private var inFlight: [String: Task<CatalogCoordinatorSnapshot, Never>] = [:]

    init(local: any LocalCatalogStore, publicStore: any PublicCatalogStore) {
        self.local = local
        self.publicStore = publicStore
    }

    func load(identifiers: [String]) async -> CatalogCoordinatorSnapshot {
        let key = Self.requestKey(identifiers)
        if let inFlight = inFlight[key] { return await inFlight.value }
        let task = Task { [weak self] in
            guard let self else { return CatalogCoordinatorSnapshot(state: .offline, documents: [], failedIdentifiers: identifiers) }
            return await self.performLoad(identifiers: identifiers)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    func refresh(identifiers: [String]) async -> CatalogCoordinatorSnapshot {
        let key = Self.requestKey(identifiers)
        if let inFlight = inFlight[key] { return await inFlight.value }
        let task = Task { [weak self] in
            guard let self else { return CatalogCoordinatorSnapshot(state: .offline, documents: [], failedIdentifiers: identifiers) }
            return await self.performRefresh(identifiers: identifiers)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    func loadAll(recordType: String, forceRefresh: Bool = false) async -> CatalogCoordinatorSnapshot {
        guard let queryStore = publicStore as? any PublicCatalogQueryStore else {
            // Older/test stores discover cards from identifiers in the manifest.
            return CatalogCoordinatorSnapshot(state: .ready, documents: [], failedIdentifiers: [])
        }
        if !forceRefresh {
            let cached = memory.values.filter { Self.recordType(of: $0) == recordType }
            if !cached.isEmpty {
                return CatalogCoordinatorSnapshot(state: .ready, documents: cached.sorted { $0.identifier < $1.identifier },
                                                  failedIdentifiers: [], servedFromCache: true)
            }
        }
        if !forceRefresh,
           let response = try? await local.fetch(CatalogQuery(identifiers: [])) {
            let cached = response.value.filter { Self.recordType(of: $0) == recordType }
            if !cached.isEmpty {
                for document in cached { memory[document.identifier] = document }
                return CatalogCoordinatorSnapshot(state: .ready, documents: cached,
                                                  failedIdentifiers: [], servedFromCache: true)
            }
        }
        do {
            let response = try await queryStore.fetchAll(recordType: recordType)
            for document in response.value { memory[document.identifier] = document }
            if !response.value.isEmpty { try? await local.replace(response.value) }
            return CatalogCoordinatorSnapshot(state: .ready, documents: response.value,
                                              failedIdentifiers: response.failedIdentifiers)
        } catch CatalogServiceError.incompatibleSchema {
            return CatalogCoordinatorSnapshot(state: .incompatibleSchema, documents: [], failedIdentifiers: [])
        } catch CatalogServiceError.offline, CatalogServiceError.unavailable, CatalogServiceError.cancelled {
            return CatalogCoordinatorSnapshot(state: .offline, documents: [], failedIdentifiers: [])
        } catch {
            return CatalogCoordinatorSnapshot(state: .emptyInstall, documents: [], failedIdentifiers: [])
        }
    }

    func clearMemory() { memory.removeAll() }

    private nonisolated static func recordType(of document: CatalogDocument) -> String? {
        guard let kind = try? document.persistedEnvelope().kind else { return nil }
        switch kind {
        case .manifest: return CloudCatalogRecordContract.RecordType.manifest
        case .creature: return CloudCatalogRecordContract.RecordType.creature
        case .evolution: return CloudCatalogRecordContract.RecordType.evolution
        case .card: return CloudCatalogRecordContract.RecordType.card
        }
    }

    private func performLoad(identifiers: [String]) async -> CatalogCoordinatorSnapshot {
        let requested = Array(Set(identifiers)).sorted()
        Self.logger.info("Loading \(requested.count, privacy: .public) catalog records")
        var documents = requested.compactMap { memory[$0] }
        var missing = requested.filter { memory[$0] == nil }
        var localWasStale = false

        if !missing.isEmpty {
            do {
                let response = try await local.fetch(CatalogQuery(identifiers: missing))
                Self.logger.info("Local catalog returned \(response.value.count, privacy: .public) records")
                documents.append(contentsOf: response.value)
                localWasStale = response.freshness == .stale
                for document in response.value { memory[document.identifier] = document }
                missing = missing.filter { !memory.keys.contains($0) }
            } catch {
                Self.logger.error("Local catalog read failed: \(String(reflecting: error), privacy: .public)")
            }
        }

        guard !missing.isEmpty else {
            return CatalogCoordinatorSnapshot(state: localWasStale ? .stale : .ready,
                                              documents: documents.sorted { $0.identifier < $1.identifier }, failedIdentifiers: [],
                                              servedFromCache: true)
        }

        do {
            Self.logger.info("Requesting \(missing.count, privacy: .public) records from public CloudKit")
            let response = try await publicStore.fetch(CatalogQuery(identifiers: missing))
            Self.logger.info("Public CloudKit returned \(response.value.count, privacy: .public) records with \(response.failedIdentifiers.count, privacy: .public) misses")
            documents.append(contentsOf: response.value)
            for document in response.value { memory[document.identifier] = document }
            if !response.value.isEmpty {
                do {
                    try await local.replace(response.value)
                } catch {
                    Self.logger.error("Local catalog write failed: \(String(reflecting: error), privacy: .public)")
                }
            }
            let state: CatalogCoordinatorState = documents.isEmpty ? .emptyInstall : (localWasStale ? .stale : .ready)
            return CatalogCoordinatorSnapshot(state: state, documents: documents.sorted { $0.identifier < $1.identifier }, failedIdentifiers: response.failedIdentifiers)
        } catch CatalogServiceError.incompatibleSchema {
            Self.logger.error("Public catalog uses an incompatible schema")
#if DEBUG
            print("BattleCardDex catalog: public catalog uses an incompatible schema")
#endif
            return CatalogCoordinatorSnapshot(state: .incompatibleSchema, documents: documents, failedIdentifiers: missing)
        } catch CatalogServiceError.offline, CatalogServiceError.unavailable, CatalogServiceError.cancelled {
            Self.logger.error("Public catalog is offline, unavailable, or cancelled")
#if DEBUG
            print("BattleCardDex catalog: public catalog is offline, unavailable, or cancelled")
#endif
            return CatalogCoordinatorSnapshot(state: documents.isEmpty ? .offline : .stale,
                                              documents: documents.sorted { $0.identifier < $1.identifier }, failedIdentifiers: missing,
                                              servedFromCache: !documents.isEmpty)
        } catch {
            Self.logger.error("Public catalog load failed: \(String(reflecting: error), privacy: .public)")
#if DEBUG
            print("BattleCardDex catalog: public catalog load failed: \(String(reflecting: error))")
#endif
            return CatalogCoordinatorSnapshot(state: documents.isEmpty ? .emptyInstall : .stale,
                                              documents: documents.sorted { $0.identifier < $1.identifier }, failedIdentifiers: missing,
                                              servedFromCache: !documents.isEmpty)
        }
    }

    /// A refresh deliberately rechecks public CloudKit even when memory/local
    /// already contain the requested IDs. Last-valid local documents remain the
    /// fallback if the service is unavailable or returns only a partial batch.
    private func performRefresh(identifiers: [String]) async -> CatalogCoordinatorSnapshot {
        let requested = Array(Set(identifiers)).sorted()
        guard !requested.isEmpty else { return CatalogCoordinatorSnapshot(state: .emptyInstall, documents: [], failedIdentifiers: []) }
        var localDocuments: [CatalogDocument] = []
        var localWasStale = false
        if let response = try? await local.fetch(CatalogQuery(identifiers: requested)) {
            localDocuments = response.value
            localWasStale = response.freshness == .stale
            for document in response.value { memory[document.identifier] = document }
        }

        do {
            let response = try await publicStore.fetch(CatalogQuery(identifiers: requested))
            var byIdentifier = Dictionary(uniqueKeysWithValues: localDocuments.map { ($0.identifier, $0) })
            for document in response.value {
                byIdentifier[document.identifier] = document
                memory[document.identifier] = document
            }
            if !response.value.isEmpty { try? await local.replace(response.value) }
            let documents = byIdentifier.values.sorted { $0.identifier < $1.identifier }
            let isPartial = !response.failedIdentifiers.isEmpty
            return CatalogCoordinatorSnapshot(state: documents.isEmpty ? .emptyInstall : (isPartial || localWasStale ? .stale : .ready),
                                              documents: documents, failedIdentifiers: response.failedIdentifiers)
        } catch CatalogServiceError.incompatibleSchema {
            return CatalogCoordinatorSnapshot(state: .incompatibleSchema, documents: localDocuments, failedIdentifiers: requested)
        } catch CatalogServiceError.offline, CatalogServiceError.unavailable, CatalogServiceError.cancelled {
            return CatalogCoordinatorSnapshot(state: localDocuments.isEmpty ? .offline : .stale,
                                              documents: localDocuments.sorted { $0.identifier < $1.identifier }, failedIdentifiers: requested)
        } catch {
            return CatalogCoordinatorSnapshot(state: localDocuments.isEmpty ? .emptyInstall : .stale,
                                              documents: localDocuments.sorted { $0.identifier < $1.identifier }, failedIdentifiers: requested)
        }
    }

    private static func requestKey(_ identifiers: [String]) -> String {
        Array(Set(identifiers)).sorted().joined(separator: "\u{1F}")
    }
}
