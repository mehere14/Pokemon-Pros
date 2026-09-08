import Foundation

/// A stable identifier plus normalized bytes at a service boundary. Domain decoding
/// belongs to the mapping layer introduced after the test harness.
nonisolated struct CatalogDocument: Equatable, Sendable {
    let identifier: String
    let payload: Data
    let contentHash: String

    init(identifier: String, envelope: CatalogPersistenceEnvelope, contentHash: String) throws {
        self.identifier = identifier
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.payload = try encoder.encode(envelope)
        self.contentHash = contentHash
    }

    func persistedEnvelope() throws -> CatalogPersistenceEnvelope {
        try CatalogPersistenceEnvelope.validatingPersistedBytes(payload)
    }
}

nonisolated struct CatalogQuery: Equatable, Sendable {
    let identifiers: [String]
}

nonisolated enum CatalogFreshness: Equatable, Sendable {
    case fresh
    case stale
}

nonisolated struct ServiceResponse<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let freshness: CatalogFreshness
    let failedIdentifiers: [String]

    init(
        value: Value,
        freshness: CatalogFreshness = .fresh,
        failedIdentifiers: [String] = []
    ) {
        self.value = value
        self.freshness = freshness
        self.failedIdentifiers = failedIdentifiers
    }
}

nonisolated enum CatalogServiceError: Error, Equatable, Sendable {
    case offline
    case throttled(retryAfter: TimeInterval)
    case unavailable
    case notFound(String)
    case malformed(String)
    case incompatibleSchema(Int)
    case cancelled
}

nonisolated protocol PublicCatalogStore: Sendable {
    func fetch(_ query: CatalogQuery) async throws -> ServiceResponse<[CatalogDocument]>
}

/// Optional capability for record families whose identifiers are not known in
/// advance. Card records use deterministic hashes, so the client discovers
/// them through paged CloudKit queries instead of an ever-growing manifest.
nonisolated protocol PublicCatalogQueryStore: Sendable {
    func fetchAll(recordType: String) async throws -> ServiceResponse<[CatalogDocument]>
}

nonisolated protocol LocalCatalogStore: Sendable {
    func fetch(_ query: CatalogQuery) async throws -> ServiceResponse<[CatalogDocument]>
    func replace(_ documents: [CatalogDocument]) async throws
    func removeAll() async throws
}

nonisolated protocol ImageRepository: Sendable {
    func data(for url: URL) async throws -> ServiceResponse<Data>
}

nonisolated protocol CatalogClock: Sendable {
    func now() async -> Date
    func sleep(for interval: TimeInterval) async throws
}

nonisolated protocol RetryScheduler: Sendable {
    func waitBeforeRetry(attempt: Int, suggestedDelay: TimeInterval?) async throws
}
