import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LoaderHTTPMethod: String, Equatable, Sendable {
    case get = "GET"
    case post = "POST"
}

public struct LoaderHTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: LoaderHTTPMethod
    public let headers: [String: String]
    public let body: Data?

    public init(url: URL, method: LoaderHTTPMethod = .get, headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct LoaderHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol LoaderTransport: Sendable {
    func send(_ request: LoaderHTTPRequest) async throws -> LoaderHTTPResponse
}

public protocol LoaderResponseCache: Sendable {
    func cachedResponse(for request: LoaderHTTPRequest) async -> LoaderHTTPResponse?
}

/// The production transport used by provider and CloudKit Web Services adapters.
/// Redirect, cookie, and credential policy remains owned by the supplied session.
public struct URLSessionLoaderTransport: LoaderTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: LoaderHTTPRequest) async throws -> LoaderHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (body, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw LoaderHTTPError.malformedResponse }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let name = entry.key as? String else { return }
            result[name] = String(describing: entry.value)
        }
        return LoaderHTTPResponse(statusCode: http.statusCode, headers: headers, body: body)
    }
}

/// Persistent, gitignored upstream snapshot cache. Only successful GET responses
/// are stored; CloudKit POST requests and credentials are never cached.
public actor CachingLoaderTransport: LoaderTransport, LoaderResponseCache {
    private struct Entry: Codable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    private let upstream: any LoaderTransport
    private let directory: URL

    public init(upstream: any LoaderTransport = URLSessionLoaderTransport(), directory: URL) {
        self.upstream = upstream
        self.directory = directory
    }

    public func send(_ request: LoaderHTTPRequest) async throws -> LoaderHTTPResponse {
        guard request.method == .get else { return try await upstream.send(request) }
        if let cached = cachedResponse(for: request) { return cached }
        let cacheURL = cacheURL(for: request)
        let response = try await upstream.send(request)
        guard (200..<300).contains(response.statusCode) else { return response }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = Entry(statusCode: response.statusCode, headers: response.headers, body: response.body)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entry).write(to: cacheURL, options: [.atomic])
        #if canImport(Darwin)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        #endif
        return response
    }

    public func cachedResponse(for request: LoaderHTTPRequest) -> LoaderHTTPResponse? {
        guard request.method == .get,
              let data = try? Data(contentsOf: cacheURL(for: request)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        return .init(statusCode: entry.statusCode, headers: entry.headers, body: entry.body)
    }

    private func cacheURL(for request: LoaderHTTPRequest) -> URL {
        directory.appendingPathComponent(Self.key(for: request)).appendingPathExtension("json")
    }

    private static func key(for request: LoaderHTTPRequest) -> String {
        // Provider API-key values are deliberately excluded from both filenames
        // and cache identity; public response content is keyed by URL alone.
        SHA256.hash(data: Data(request.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public protocol LoaderClock: Sendable {
    func now() async -> Date
    func sleep(for interval: TimeInterval) async throws
}

public struct SystemLoaderClock: LoaderClock {
    public init() {}
    public func now() async -> Date { Date() }
    public func sleep(for interval: TimeInterval) async throws {
        guard interval > 0 else { return }
        try await Task.sleep(for: .seconds(interval))
    }
}

public struct LoaderHTTPPolicy: Equatable, Sendable {
    public let minimumRequestInterval: TimeInterval
    public let maximumConcurrentRequests: Int
    public let maximumAttempts: Int
    public let baseRetryDelay: TimeInterval
    public let maximumRetryDelay: TimeInterval

    public init(minimumRequestInterval: TimeInterval = 0.1, maximumConcurrentRequests: Int = 4,
                maximumAttempts: Int = 4, baseRetryDelay: TimeInterval = 0.5,
                maximumRetryDelay: TimeInterval = 30) {
        self.minimumRequestInterval = max(0, minimumRequestInterval)
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.maximumAttempts = max(1, maximumAttempts)
        self.baseRetryDelay = max(0, baseRetryDelay)
        self.maximumRetryDelay = max(self.baseRetryDelay, maximumRetryDelay)
    }
}

public enum LoaderHTTPError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidURL
    case httpStatus(Int, retryAfter: TimeInterval?)
    case malformedResponse
    case duplicateCursor(String)
    case missingNextCursor

    public var description: String {
        switch self {
        case .invalidURL: "invalid upstream URL"
        case let .httpStatus(status, retryAfter): "upstream HTTP \(status)\(retryAfter.map { "; retry-after \($0)s" } ?? "")"
        case .malformedResponse: "malformed upstream response"
        case let .duplicateCursor(cursor): "duplicate pagination cursor: \(cursor)"
        case .missingNextCursor: "pagination response omitted its next cursor"
        }
    }
}

public actor LoaderRequestGate {
    private let policy: LoaderHTTPPolicy
    private let clock: any LoaderClock
    private var lastRequestAt: Date?
    private var inFlight = 0

    public init(policy: LoaderHTTPPolicy, clock: any LoaderClock) {
        self.policy = policy
        self.clock = clock
    }

    public func acquire() async throws {
        while inFlight >= policy.maximumConcurrentRequests {
            try await clock.sleep(for: 0.01)
        }
        let current = await clock.now()
        if let lastRequestAt {
            let wait = policy.minimumRequestInterval - current.timeIntervalSince(lastRequestAt)
            if wait > 0 { try await clock.sleep(for: wait) }
        }
        lastRequestAt = await clock.now()
        inFlight += 1
    }

    public func release() { inFlight = max(0, inFlight - 1) }
}

/// Shares an identical in-flight request (URL + headers) between concurrent
/// callers. The response is shared, while each caller still decodes it into its
/// own requested type.
private actor LoaderRequestCoalescer {
    private var inFlight: [String: Task<LoaderHTTPResponse, Error>] = [:]

    func response(for key: String,
                  operation: @escaping @Sendable () async throws -> LoaderHTTPResponse) async throws -> LoaderHTTPResponse {
        if let task = inFlight[key] { return try await task.value }
        let task = Task { try await operation() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }
}

public struct LoaderHTTPClient: Sendable {
    private let transport: any LoaderTransport
    private let policy: LoaderHTTPPolicy
    private let clock: any LoaderClock
    private let gate: LoaderRequestGate
    private let coalescer = LoaderRequestCoalescer()
    private let jitter: @Sendable (Int) -> TimeInterval

    public init(transport: any LoaderTransport, policy: LoaderHTTPPolicy = .init(), clock: any LoaderClock = SystemLoaderClock(),
                jitter: @escaping @Sendable (Int) -> TimeInterval = { _ in 0 }) {
        self.transport = transport
        self.policy = policy
        self.clock = clock
        self.gate = LoaderRequestGate(policy: policy, clock: clock)
        self.jitter = jitter
    }

    public func get<Value: Decodable>(_ request: LoaderHTTPRequest, as type: Value.Type = Value.self) async throws -> Value {
        let response = try await coalescer.response(for: Self.coalescingKey(request)) {
            try await self.sendWithRetries(request)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw LoaderHTTPError.httpStatus(response.statusCode, retryAfter: Self.retryAfter(from: response.headers))
        }
        do { return try JSONDecoder().decode(Value.self, from: response.body) }
        catch { throw LoaderHTTPError.malformedResponse }
    }

    public func fetchAll<Value: Decodable>(baseURL: URL, path: String, query: [URLQueryItem] = [],
                                           decodePage: @escaping @Sendable (Data) throws -> ([Value], String?)) async throws -> [Value] {
        var cursor: String?
        var seen: Set<String> = []
        var all: [Value] = []
        while true {
            var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            var queryItems = query
            if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
            components?.queryItems = queryItems
            guard let url = components?.url else { throw LoaderHTTPError.invalidURL }
            let page: PageData<Value> = try await rawPage(LoaderHTTPRequest(url: url), decodePage: decodePage)
            all.append(contentsOf: page.items)
            guard let next = page.nextCursor else { return all }
            guard seen.insert(next).inserted else { throw LoaderHTTPError.duplicateCursor(next) }
            cursor = next
        }
    }

    private struct PageData<Value> {
        let items: [Value]
        let nextCursor: String?
    }

    private func rawPage<Value>(_ request: LoaderHTTPRequest, decodePage: @escaping @Sendable (Data) throws -> ([Value], String?)) async throws -> PageData<Value> {
        let response = try await coalescer.response(for: Self.coalescingKey(request)) {
            try await self.sendWithRetries(request)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw LoaderHTTPError.httpStatus(response.statusCode, retryAfter: Self.retryAfter(from: response.headers))
        }
        do {
            let (items, cursor) = try decodePage(response.body)
            return PageData(items: items, nextCursor: cursor)
        } catch { throw LoaderHTTPError.malformedResponse }
    }

    private func sendWithRetries(_ request: LoaderHTTPRequest) async throws -> LoaderHTTPResponse {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            if let cache = transport as? any LoaderResponseCache,
               let cached = await cache.cachedResponse(for: request) {
                return cached
            }
            try await gate.acquire()
            let response: LoaderHTTPResponse
            do { response = try await transport.send(request) }
            catch {
                await gate.release()
                guard attempt + 1 < policy.maximumAttempts else { throw error }
                try await retryDelay(attempt: attempt, suggested: nil); attempt += 1; continue
            }
            await gate.release()
            guard (200..<300).contains(response.statusCode) else {
                let retryAfter = Self.retryAfter(from: response.headers)
                let transient = response.statusCode == 408 || response.statusCode == 425 || response.statusCode == 429 || response.statusCode >= 500
                guard transient, attempt + 1 < policy.maximumAttempts else { return response }
                try await retryDelay(attempt: attempt, suggested: retryAfter); attempt += 1; continue
            }
            return response
        }
    }

    private func retryDelay(attempt: Int, suggested: TimeInterval?) async throws {
        let exponential = min(policy.maximumRetryDelay, policy.baseRetryDelay * pow(2, Double(attempt)))
        let delay = min(policy.maximumRetryDelay, max(0, suggested ?? 0) > 0 ? suggested! : exponential + max(0, jitter(attempt)))
        try await clock.sleep(for: delay)
    }

    private static func retryAfter(from headers: [String: String]) -> TimeInterval? {
        let value = headers.first { $0.key.lowercased() == "retry-after" }?.value
        return value.flatMap(TimeInterval.init)
    }

    private static func coalescingKey(_ request: LoaderHTTPRequest) -> String {
        request.method.rawValue + "\n" + request.url.absoluteString + "\n"
            + request.headers.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: "\n")
            + "\n" + (request.body?.base64EncodedString() ?? "")
    }
}
