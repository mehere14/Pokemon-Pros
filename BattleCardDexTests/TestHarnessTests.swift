import Foundation
import SwiftData
import Testing
@testable import Battle_Card_Dex

@Suite(.serialized)
struct TestHarnessTests {
    private var documents: [CatalogDocument] { [try! .fixture()] }

    @Test func normalizedFixturesDecodeDeterministically() throws {
        let firstCreatures = try DeterministicFixtures.creatureIndex()
        let secondCreatures = try DeterministicFixtures.creatureIndex()
        let firstEvolutions = try DeterministicFixtures.evolutions()
        let secondEvolutions = try DeterministicFixtures.evolutions()
        let firstCards = try DeterministicFixtures.battleCards()
        let secondCards = try DeterministicFixtures.battleCards()

        #expect(firstCreatures == secondCreatures)
        #expect(firstEvolutions == secondEvolutions)
        #expect(firstCards == secondCards)
        #expect(firstCreatures.creatures.map(\.id) == Array(1...6))
        #expect(firstCreatures.creatures.map(\.id) == firstCreatures.creatures.map(\.id).sorted())
        #expect(firstEvolutions.chains.first?.edges.count == 3)
        #expect(firstEvolutions.chains.last?.rootID == 6)
        #expect(firstEvolutions.chains.last?.edges.isEmpty == true)
        #expect(firstCards.cards.count == 3)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(firstCreatures) == encoder.encode(secondCreatures))
        #expect(try encoder.encode(firstEvolutions) == encoder.encode(secondEvolutions))
        #expect(try encoder.encode(firstCards) == encoder.encode(secondCards))
        #expect(try CatalogDocument.fixture().payload == CatalogDocument.fixture().payload)
    }

    @Test func fixturesContainNoProhibitedTerminology() throws {
        let scalars = [112, 111, 107, 101, 109, 111, 110]
        let prohibited = String(String.UnicodeScalarView(scalars.compactMap(UnicodeScalar.init)))
        let accentedScalars = [112, 111, 107, 233, 109, 111, 110]
        let accented = String(String.UnicodeScalarView(accentedScalars.compactMap(UnicodeScalar.init)))

        for name in ["creature-index-1-6", "evolution-cases", "battle-cards"] {
            let text = try #require(String(data: DeterministicFixtures.data(named: name), encoding: .utf8))
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            #expect(!text.contains(prohibited))
            #expect(!text.contains(accented.folding(options: .diacriticInsensitive, locale: nil)))
        }
    }

    @Test func publicCatalogFakeEmitsEveryRequiredState() async throws {
        let fake = FakePublicCatalogStore(states: [
            .success(documents),
            .empty,
            .stale(documents),
            .offline,
            .throttle(retryAfter: 7),
            .partialFailure(documents, failedIdentifiers: ["creature-2"]),
            .cancellation,
        ])
        let query = CatalogQuery(identifiers: ["creature-1", "creature-2"])

        let success = try await fake.fetch(query)
        #expect(success == ServiceResponse(value: documents))
        let empty = try await fake.fetch(query)
        #expect(empty.value.isEmpty)
        let stale = try await fake.fetch(query)
        #expect(stale.freshness == .stale)

        await expectCatalogError(.offline) { try await fake.fetch(query) }
        await expectCatalogError(.throttled(retryAfter: 7)) { try await fake.fetch(query) }

        let partial = try await fake.fetch(query)
        #expect(partial.value == documents)
        #expect(partial.failedIdentifiers == ["creature-2"])
        await expectCancellation { try await fake.fetch(query) }
        // Read actor-isolated state before invoking the expectation macro. Keeping
        // `await` inside the macro made this assertion intermittent when Swift
        // Testing executed other suites concurrently on the simulator.
        let receivedQueries = await fake.receivedQueries
        #expect(receivedQueries == Array(repeating: query, count: 7))
    }

    @Test func localCatalogAndImageFakesRecordDeterministicCalls() async throws {
        let local = FakeLocalCatalogStore(states: [.success(documents), .empty])
        let query = CatalogQuery(identifiers: ["creature-1"])
        #expect(try await local.fetch(query).value == documents)
        try await local.replace(documents)
        try await local.removeAll()
        #expect(await local.replacements.isEmpty)
        #expect(await local.removeAllCallCount == 1)

        let bytes = Data([0, 1, 2, 3])
        let image = FakeImageRepository(states: [.success(bytes), .empty])
        let url = try #require(URL(string: "https://images.invalid/fixture.png"))
        #expect(try await image.data(for: url).value == bytes)
        #expect(try await image.data(for: url).value.isEmpty)
        #expect(await image.requestedURLs == [url, url])
    }

    @Test func clockAndRetrySchedulerNeverWaitOnWallTime() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = FakeCatalogClock(now: start)
        #expect(await clock.now() == start)
        try await clock.sleep(for: 2.5)
        #expect(await clock.now() == start.addingTimeInterval(2.5))
        #expect(await clock.requestedSleeps == [2.5])

        let retry = FakeRetryScheduler()
        try await retry.waitBeforeRetry(attempt: 1, suggestedDelay: 3)
        #expect(await retry.requests == [.init(attempt: 1, suggestedDelay: 3)])
        await retry.setCancellationAttempt(2)
        await expectCancellation { try await retry.waitBeforeRetry(attempt: 2, suggestedDelay: nil) }
    }

    @Test func everyInMemoryContainerStartsEmptyAndIsIsolated() throws {
        let first = try InMemoryTestStore.makeContainer()
        let second = try InMemoryTestStore.makeContainer()
        let firstContext = ModelContext(first)
        let secondContext = ModelContext(second)

        #expect(try firstContext.fetchCount(FetchDescriptor<CachedCreature>()) == 0)
        #expect(try secondContext.fetchCount(FetchDescriptor<CachedCreature>()) == 0)
        firstContext.insert(CachedCreature(
            sourceID: 1, recordIdentifier: "creature-1", sortIndex: 1,
            normalizedName: "seed-creature", displayName: "Seed Creature", generation: "generation-1",
            typeIndex: "|leaf|", contentHash: "hash", schemaVersion: 1,
            cachedAt: Date(timeIntervalSince1970: 1), encodedPayload: Data()
        ))
        try firstContext.save()
        #expect(try firstContext.fetchCount(FetchDescriptor<CachedCreature>()) == 1)
        #expect(try secondContext.fetchCount(FetchDescriptor<CachedCreature>()) == 0)
    }

    @Test func developmentNamespacesAreIsolatedAndProductionIsDenied() throws {
        let first = try DevelopmentCloudRecordNamespace(
            service: .developmentPublicDatabase,
            runIdentifier: "Run A / Worker 1"
        )
        let second = try DevelopmentCloudRecordNamespace(
            service: .developmentPublicDatabase,
            runIdentifier: "Run B / Worker 1"
        )
        #expect(first.prefix == "development-test-run-a-worker-1")
        #expect(first.recordName(for: "creature-1") != second.recordName(for: "creature-1"))
        #expect(throws: TestCloudIsolationError.productionAccessDenied) {
            try DevelopmentCloudRecordNamespace(
                service: .productionPublicDatabase,
                runIdentifier: "must-fail"
            )
        }
        #expect(throws: TestCloudIsolationError.developmentEnvironmentRequired) {
            try DevelopmentCloudRecordNamespace(service: .fake, runIdentifier: "must-fail")
        }
    }

    private func expectCatalogError(
        _ expected: CatalogServiceError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected catalog service error")
        } catch let error as CatalogServiceError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func expectCancellation(operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private extension FakeRetryScheduler {
    func setCancellationAttempt(_ attempt: Int?) {
        cancellationAttempt = attempt
    }
}
