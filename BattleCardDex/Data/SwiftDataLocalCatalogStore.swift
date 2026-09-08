import Foundation
import SwiftData

enum LocalCatalogStoreError: Error, Equatable, Sendable {
    case emptyIdentifier
    case emptyContentHash
    case invalidSourceIdentifier(String)
}

struct LocalCatalogStatistics: Equatable, Sendable {
    let manifests: Int
    let creatures: Int
    let evolutionChains: Int
    let cards: Int
}

actor SwiftDataLocalCatalogStore: LocalCatalogStore {
    private let container: ModelContainer
    private let now: @Sendable () -> Date

    init(container: ModelContainer, now: @escaping @Sendable () -> Date = Date.init) {
        self.container = container
        self.now = now
    }

    func fetch(_ query: CatalogQuery) async throws -> ServiceResponse<[CatalogDocument]> {
        let context = ModelContext(container)
        let requested = Set(query.identifiers)
        var documents: [CatalogDocument] = []
        for row in try context.fetch(FetchDescriptor<CachedCatalogManifest>()) where requested.isEmpty || requested.contains(row.recordIdentifier) {
            documents.append(.init(identifier: row.recordIdentifier, payload: row.encodedPayload, contentHash: row.contentHash))
        }
        for row in try context.fetch(FetchDescriptor<CachedCreature>()) where requested.isEmpty || requested.contains(row.recordIdentifier) {
            documents.append(.init(identifier: row.recordIdentifier, payload: row.encodedPayload, contentHash: row.contentHash))
        }
        for row in try context.fetch(FetchDescriptor<CachedEvolutionChain>()) where requested.isEmpty || requested.contains(row.recordIdentifier) {
            documents.append(.init(identifier: row.recordIdentifier, payload: row.encodedPayload, contentHash: row.contentHash))
        }
        for row in try context.fetch(FetchDescriptor<CachedCard>()) where requested.isEmpty || requested.contains(row.recordIdentifier) {
            documents.append(.init(identifier: row.recordIdentifier, payload: row.encodedPayload, contentHash: row.contentHash))
        }
        documents.sort { $0.identifier < $1.identifier }
        return ServiceResponse(value: documents)
    }

    /// Validates and decodes the complete batch before opening the transaction.
    /// Duplicate stable source IDs use a documented last-input-wins rule.
    func replace(_ documents: [CatalogDocument]) async throws {
        let prepared = try Self.prepare(documents)
        let context = ModelContext(container)
        do {
            try context.transaction {
                for item in prepared { try Self.upsert(item, in: context, at: now()) }
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func removeAll() async throws {
        let context = ModelContext(container)
        try context.transaction {
            try context.fetch(FetchDescriptor<CachedCatalogManifest>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<CachedCreature>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<CachedEvolutionChain>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<CachedCard>()).forEach(context.delete)
        }
    }

    func manifest(sourceID: String) throws -> CatalogManifestPayload? {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<CachedCatalogManifest>())
            .first { $0.sourceID == sourceID }
            .map { try Self.decode($0.encodedPayload, as: CatalogManifestPayload.self) }
    }

    func creatures(search: String? = nil, generation: String? = nil, type: String? = nil) throws -> [CatalogCreaturePayload] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let generation = generation?.lowercased()
        let typeToken = type.map { Self.indexToken($0.lowercased()) }
        return try ModelContext(container).fetch(FetchDescriptor<CachedCreature>())
            .filter { row in
                (query == nil || query!.isEmpty || row.normalizedName.localizedStandardContains(query!) || String(row.sourceID).contains(query!)) &&
                (generation == nil || row.generation?.lowercased() == generation) &&
                (typeToken == nil || row.typeIndex.contains(typeToken!))
            }
            .sorted { ($0.sortIndex, $0.normalizedName) < ($1.sortIndex, $1.normalizedName) }
            .map { try Self.decode($0.encodedPayload, as: CatalogCreaturePayload.self) }
    }

    func evolution(containing creatureID: Int) throws -> CatalogEvolutionPayload? {
        let token = Self.indexToken(String(creatureID))
        return try ModelContext(container).fetch(FetchDescriptor<CachedEvolutionChain>())
            .filter { $0.memberIDIndex.contains(token) }
            .sorted { $0.sourceID < $1.sourceID }
            .first
            .map { try Self.decode($0.encodedPayload, as: CatalogEvolutionPayload.self) }
    }

    func cards(relatedTo creatureID: Int, search: String? = nil) throws -> [CatalogCardPayload] {
        let token = Self.indexToken(String(creatureID))
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try ModelContext(container).fetch(FetchDescriptor<CachedCard>())
            .filter { row in
                row.relatedCreatureIDIndex.contains(token) &&
                (query == nil || query!.isEmpty || row.normalizedName.localizedStandardContains(query!) || row.collectorNumber.localizedStandardContains(query!))
            }
            .sorted { ($0.setID, $0.collectorNumber, $0.sourceID) < ($1.setID, $1.collectorNumber, $1.sourceID) }
            .map { try Self.decode($0.encodedPayload, as: CatalogCardPayload.self) }
    }

    func statistics() throws -> LocalCatalogStatistics {
        let context = ModelContext(container)
        return try LocalCatalogStatistics(
            manifests: context.fetchCount(FetchDescriptor<CachedCatalogManifest>()),
            creatures: context.fetchCount(FetchDescriptor<CachedCreature>()),
            evolutionChains: context.fetchCount(FetchDescriptor<CachedEvolutionChain>()),
            cards: context.fetchCount(FetchDescriptor<CachedCard>())
        )
    }

    private enum Prepared {
        case manifest(CatalogDocument, CatalogManifestPayload)
        case creature(CatalogDocument, CatalogCreaturePayload)
        case evolution(CatalogDocument, CatalogEvolutionPayload)
        case card(CatalogDocument, CatalogCardPayload)

        var key: String {
            switch self {
            case .manifest(_, let value): "0-\(value.id)"
            case .creature(_, let value): "1-\(value.id)"
            case .evolution(_, let value): "2-\(value.id)"
            case .card(_, let value): "3-\(value.id)"
            }
        }
    }

    private static func prepare(_ documents: [CatalogDocument]) throws -> [Prepared] {
        var unique: [String: Prepared] = [:]
        for document in documents {
            guard !document.identifier.isEmpty else { throw LocalCatalogStoreError.emptyIdentifier }
            guard !document.contentHash.isEmpty else { throw LocalCatalogStoreError.emptyContentHash }
            let envelope = try document.persistedEnvelope()
            let item: Prepared
            switch envelope.kind {
            case .manifest:
                let value = try envelope.decode(CatalogManifestPayload.self)
                guard !value.id.isEmpty else { throw LocalCatalogStoreError.invalidSourceIdentifier(value.id) }
                item = .manifest(document, value)
            case .creature:
                let value = try envelope.decode(CatalogCreaturePayload.self)
                guard value.id > 0 else { throw LocalCatalogStoreError.invalidSourceIdentifier(String(value.id)) }
                item = .creature(document, value)
            case .evolution:
                let value = try envelope.decode(CatalogEvolutionPayload.self)
                guard value.id > 0 else { throw LocalCatalogStoreError.invalidSourceIdentifier(String(value.id)) }
                item = .evolution(document, value)
            case .card:
                let value = try envelope.decode(CatalogCardPayload.self)
                guard !value.id.isEmpty else { throw LocalCatalogStoreError.invalidSourceIdentifier(value.id) }
                item = .card(document, value)
            }
            unique[item.key] = item
        }
        return unique.values.sorted { $0.key < $1.key }
    }

    private static func upsert(_ item: Prepared, in context: ModelContext, at date: Date) throws {
        switch item {
        case .manifest(let document, let value):
            if let row = try context.fetch(FetchDescriptor<CachedCatalogManifest>()).first(where: { $0.sourceID == value.id }) {
                guard row.contentHash != document.contentHash else { return }
                row.recordIdentifier = document.identifier; row.revision = value.revision; row.contentHash = document.contentHash
                row.schemaVersion = value.schemaVersion; row.cachedAt = date; row.sourceUpdatedAt = value.publishedAt; row.encodedPayload = document.payload
            } else {
                context.insert(CachedCatalogManifest(sourceID: value.id, recordIdentifier: document.identifier, revision: value.revision, contentHash: document.contentHash, schemaVersion: value.schemaVersion, cachedAt: date, sourceUpdatedAt: value.publishedAt, encodedPayload: document.payload))
            }
        case .creature(let document, let value):
            let typeIndex = indexed(value.types)
            if let row = try context.fetch(FetchDescriptor<CachedCreature>()).first(where: { $0.sourceID == value.id }) {
                guard row.contentHash != document.contentHash else { return }
                row.recordIdentifier = document.identifier; row.sortIndex = value.id; row.normalizedName = value.name
                row.displayName = value.displayName; row.generation = value.generation; row.typeIndex = typeIndex
                row.contentHash = document.contentHash; row.schemaVersion = value.schemaVersion; row.cachedAt = date; row.encodedPayload = document.payload
            } else {
                context.insert(CachedCreature(sourceID: value.id, recordIdentifier: document.identifier, sortIndex: value.id, normalizedName: value.name, displayName: value.displayName, generation: value.generation, typeIndex: typeIndex, contentHash: document.contentHash, schemaVersion: value.schemaVersion, cachedAt: date, encodedPayload: document.payload))
            }
        case .evolution(let document, let value):
            let members = indexed(memberIDs(in: value.root).map(String.init))
            if let row = try context.fetch(FetchDescriptor<CachedEvolutionChain>()).first(where: { $0.sourceID == value.id }) {
                guard row.contentHash != document.contentHash else { return }
                row.recordIdentifier = document.identifier; row.memberIDIndex = members; row.contentHash = document.contentHash
                row.schemaVersion = value.schemaVersion; row.cachedAt = date; row.encodedPayload = document.payload
            } else {
                context.insert(CachedEvolutionChain(sourceID: value.id, recordIdentifier: document.identifier, memberIDIndex: members, contentHash: document.contentHash, schemaVersion: value.schemaVersion, cachedAt: date, encodedPayload: document.payload))
            }
        case .card(let document, let value):
            let related = indexed(value.relatedCreatureIDs.map(String.init))
            if let row = try context.fetch(FetchDescriptor<CachedCard>()).first(where: { $0.sourceID == value.id }) {
                guard row.contentHash != document.contentHash else { return }
                row.recordIdentifier = document.identifier; row.normalizedName = value.name.lowercased(); row.collectorNumber = value.collectorNumber
                row.setID = value.setID; row.relatedCreatureIDIndex = related; row.contentHash = document.contentHash
                row.schemaVersion = value.schemaVersion; row.cachedAt = date; row.encodedPayload = document.payload
            } else {
                context.insert(CachedCard(sourceID: value.id, recordIdentifier: document.identifier, normalizedName: value.name.lowercased(), collectorNumber: value.collectorNumber, setID: value.setID, relatedCreatureIDIndex: related, contentHash: document.contentHash, schemaVersion: value.schemaVersion, cachedAt: date, encodedPayload: document.payload))
            }
        }
    }

    private static func decode<Value: NormalizedCatalogPayload>(_ bytes: Data, as type: Value.Type) throws -> Value {
        try CatalogPersistenceEnvelope.validatingPersistedBytes(bytes).decode(type)
    }

    private static func memberIDs(in node: CatalogEvolutionNode) -> [Int] {
        [node.creatureID] + node.children.flatMap(memberIDs(in:))
    }

    private static func indexed<S: Sequence>(_ values: S) -> String where S.Element == String {
        "|" + Array(Set(values.map { $0.lowercased() })).sorted().joined(separator: "|") + "|"
    }

    private static func indexToken(_ value: String) -> String { "|\(value)|" }
}

nonisolated private extension CatalogDocument {
    nonisolated init(identifier: String, payload: Data, contentHash: String) {
        self.identifier = identifier
        self.payload = payload
        self.contentHash = contentHash
    }
}
