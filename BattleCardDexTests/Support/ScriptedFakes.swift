import Foundation
@testable import Battle_Card_Dex

nonisolated enum ScriptedServiceState<Value: Equatable & Sendable>: Equatable, Sendable {
    case success(Value)
    case empty
    case stale(Value)
    case offline
    case throttle(retryAfter: TimeInterval)
    case partialFailure(Value, failedIdentifiers: [String])
    case cancellation
}

nonisolated private func resolve<Value: Equatable & Sendable>(
    _ state: ScriptedServiceState<Value>,
    emptyValue: @autoclosure () -> Value
) throws -> ServiceResponse<Value> {
    switch state {
    case .success(let value):
        return ServiceResponse(value: value)
    case .empty:
        return ServiceResponse(value: emptyValue())
    case .stale(let value):
        return ServiceResponse(value: value, freshness: .stale)
    case .offline:
        throw CatalogServiceError.offline
    case .throttle(let retryAfter):
        throw CatalogServiceError.throttled(retryAfter: retryAfter)
    case .partialFailure(let value, let identifiers):
        return ServiceResponse(value: value, failedIdentifiers: identifiers)
    case .cancellation:
        throw CancellationError()
    }
}

actor FakePublicCatalogStore: PublicCatalogStore {
    private var states: [ScriptedServiceState<[CatalogDocument]>]
    private(set) var receivedQueries: [CatalogQuery] = []

    init(states: [ScriptedServiceState<[CatalogDocument]>]) {
        self.states = states
    }

    func fetch(_ query: CatalogQuery) async throws -> ServiceResponse<[CatalogDocument]> {
        receivedQueries.append(query)
        precondition(!states.isEmpty, "A fake service must be fully scripted")
        return try resolve(states.removeFirst(), emptyValue: [])
    }
}

actor FakeLocalCatalogStore: LocalCatalogStore {
    private var fetchStates: [ScriptedServiceState<[CatalogDocument]>]
    private(set) var replacements: [[CatalogDocument]] = []
    private(set) var removeAllCallCount = 0

    init(states: [ScriptedServiceState<[CatalogDocument]>] = [.empty]) {
        fetchStates = states
    }

    func fetch(_ query: CatalogQuery) async throws -> ServiceResponse<[CatalogDocument]> {
        precondition(!fetchStates.isEmpty, "A fake service must be fully scripted")
        return try resolve(fetchStates.removeFirst(), emptyValue: [])
    }

    func replace(_ documents: [CatalogDocument]) async throws {
        replacements.append(documents)
    }

    func removeAll() async throws {
        removeAllCallCount += 1
        replacements.removeAll()
    }
}

actor FakeImageRepository: ImageRepository {
    private var states: [ScriptedServiceState<Data>]
    private(set) var requestedURLs: [URL] = []

    init(states: [ScriptedServiceState<Data>]) {
        self.states = states
    }

    func data(for url: URL) async throws -> ServiceResponse<Data> {
        requestedURLs.append(url)
        precondition(!states.isEmpty, "A fake service must be fully scripted")
        return try resolve(states.removeFirst(), emptyValue: Data())
    }
}

actor FakeCatalogClock: CatalogClock {
    private var instant: Date
    private(set) var requestedSleeps: [TimeInterval] = []

    init(now: Date) {
        instant = now
    }

    func now() -> Date { instant }

    func sleep(for interval: TimeInterval) throws {
        try Task.checkCancellation()
        requestedSleeps.append(interval)
        instant.addTimeInterval(interval)
    }
}

actor FakeRetryScheduler: RetryScheduler {
    nonisolated struct Request: Equatable, Sendable {
        let attempt: Int
        let suggestedDelay: TimeInterval?
    }

    private(set) var requests: [Request] = []
    var cancellationAttempt: Int?

    func waitBeforeRetry(attempt: Int, suggestedDelay: TimeInterval?) throws {
        if cancellationAttempt == attempt { throw CancellationError() }
        requests.append(Request(attempt: attempt, suggestedDelay: suggestedDelay))
    }
}
