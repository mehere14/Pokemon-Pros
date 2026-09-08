import Foundation
import Testing
@testable import BattleCardDexLoaderCore

private actor ScriptedTransport: LoaderTransport {
    var responses: [Result<LoaderHTTPResponse, Error>]
    var requests: [LoaderHTTPRequest] = []

    init(_ responses: [Result<LoaderHTTPResponse, Error>]) { self.responses = responses }

    func send(_ request: LoaderHTTPRequest) async throws -> LoaderHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw LoaderHTTPError.malformedResponse }
        return try responses.removeFirst().get()
    }
}

private actor SlowTransport: LoaderTransport {
    private(set) var callCount = 0

    func send(_ request: LoaderHTTPRequest) async throws -> LoaderHTTPResponse {
        callCount += 1
        try await Task.sleep(for: .milliseconds(20))
        return LoaderHTTPResponse(statusCode: 200, body: Data(#"{"value":9}"#.utf8))
    }
}

private actor TestClock: LoaderClock {
    var current = Date(timeIntervalSince1970: 1_000)
    var sleeps: [TimeInterval] = []
    func now() async -> Date { current }
    func sleep(for interval: TimeInterval) async throws {
        sleeps.append(interval)
        current = current.addingTimeInterval(max(0, interval))
    }
}

private struct NumberEnvelope: Decodable { let value: Int }

@Test("HTTP client retries throttles and honors retry-after")
func retriesThrottle() async throws {
    let clock = TestClock()
    let transport = ScriptedTransport([
        .success(LoaderHTTPResponse(statusCode: 429, headers: ["Retry-After": "3"])),
        .success(LoaderHTTPResponse(statusCode: 200, body: Data(#"{"value":7}"#.utf8)))
    ])
    let client = LoaderHTTPClient(transport: transport, policy: LoaderHTTPPolicy(minimumRequestInterval: 0, maximumAttempts: 2), clock: clock)
    let value = try await client.get(LoaderHTTPRequest(url: URL(string: "https://example.test/item")!), as: NumberEnvelope.self)
    #expect(value.value == 7)
    #expect(await clock.sleeps.contains(3))
    #expect((await transport.requests).count == 2)
}

@Test("permanent HTTP failures are not retried")
func permanentFailure() async throws {
    let clock = TestClock()
    let transport = ScriptedTransport([.success(LoaderHTTPResponse(statusCode: 404))])
    let client = LoaderHTTPClient(transport: transport, policy: LoaderHTTPPolicy(maximumAttempts: 4), clock: clock)
    await #expect(throws: LoaderHTTPError.httpStatus(404, retryAfter: nil)) {
        _ = try await client.get(LoaderHTTPRequest(url: URL(string: "https://example.test/item")!), as: NumberEnvelope.self)
    }
    #expect((await transport.requests).count == 1)
}

@Test("identical concurrent requests share one transport call")
func identicalRequestsCoalesce() async throws {
    let transport = SlowTransport()
    let client = LoaderHTTPClient(transport: transport, policy: LoaderHTTPPolicy(minimumRequestInterval: 0))
    let request = LoaderHTTPRequest(url: URL(string: "https://example.test/shared")!)
    let values = await withTaskGroup(of: Int?.self, returning: [Int].self) { group in
        for _ in 0..<4 {
            group.addTask {
                try? await client.get(request, as: NumberEnvelope.self).value
            }
        }
        var result: [Int] = []
        for await value in group { if let value { result.append(value) } }
        return result
    }
    #expect(values.sorted() == [9, 9, 9, 9])
    #expect(await transport.callCount == 1)
}

@Test("pagination consumes every cursor exactly once")
func pagination() async throws {
    let transport = ScriptedTransport([
        .success(LoaderHTTPResponse(statusCode: 200, body: Data(#"{"items":[1,2],"next":"b"}"#.utf8))),
        .success(LoaderHTTPResponse(statusCode: 200, body: Data(#"{"items":[3],"next":null}"#.utf8)))
    ])
    let client = LoaderHTTPClient(transport: transport, policy: LoaderHTTPPolicy(minimumRequestInterval: 0))
    let values = try await client.fetchAll(baseURL: URL(string: "https://example.test")!, path: "items") { data in
        struct Page: Decodable { let items: [Int]; let next: String? }
        let page = try JSONDecoder().decode(Page.self, from: data)
        return (page.items, page.next)
    }
    #expect(values == [1, 2, 3])
    #expect((await transport.requests).map(\.url.absoluteString).contains { $0.contains("cursor=b") })
}

@Test("pagination rejects a repeated cursor")
func repeatedCursor() async throws {
    let transport = ScriptedTransport([
        .success(LoaderHTTPResponse(statusCode: 200, body: Data(#"{"items":[1],"next":"same"}"#.utf8))),
        .success(LoaderHTTPResponse(statusCode: 200, body: Data(#"{"items":[2],"next":"same"}"#.utf8)))
    ])
    let client = LoaderHTTPClient(transport: transport, policy: LoaderHTTPPolicy(minimumRequestInterval: 0))
    await #expect(throws: LoaderHTTPError.duplicateCursor("same")) {
        _ = try await client.fetchAll(baseURL: URL(string: "https://example.test")!, path: "items") { data in
            struct Page: Decodable { let items: [Int]; let next: String? }
            let page = try JSONDecoder().decode(Page.self, from: data)
            return (page.items, page.next)
        }
    }
}

@Test("successful provider responses are reused from the persistent cache")
func persistentProviderCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let upstream = ScriptedTransport([.success(.init(statusCode: 200, headers: ["ETag": "fixture"], body: Data(#"{"value":42}"#.utf8)))])
    let cached = CachingLoaderTransport(upstream: upstream, directory: directory)
    let request = LoaderHTTPRequest(url: URL(string: "https://example.test/provider/42")!)

    let first = try await cached.send(request)
    let second = try await cached.send(request)
    #expect(first == second)
    #expect((await upstream.requests).count == 1)
    #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).count == 1)
}

@Test("CloudKit POST requests are never stored in the provider cache")
func providerCacheDoesNotStorePosts() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let upstream = ScriptedTransport([.success(.init(statusCode: 200, body: Data(#"{"records":[]}"#.utf8)))])
    let cached = CachingLoaderTransport(upstream: upstream, directory: directory)
    _ = try await cached.send(.init(url: URL(string: "https://example.test/records/lookup")!, method: .post, body: Data()))
    #expect((await upstream.requests).count == 1)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}
