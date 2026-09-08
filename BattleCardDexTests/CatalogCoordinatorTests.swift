import Foundation
import Testing
@testable import Battle_Card_Dex

@Suite(.serialized)
struct CatalogCoordinatorTests {
    @Test func coldInstallUsesPublicAndPersistsLocally() async throws {
        let document = try CatalogDocument.fixture()
        let local = FakeLocalCatalogStore(states: [.empty])
        let publicStore = FakePublicCatalogStore(states: [.success([document])])
        let coordinator = CatalogCoordinator(local: local, publicStore: publicStore)
        let result = await coordinator.load(identifiers: [document.identifier])
        #expect(result.state == .ready)
        #expect(result.documents == [document])
        #expect((await publicStore.receivedQueries).count == 1)
        #expect((await local.replacements).count == 1)
    }

    @Test func warmLaunchUsesLocalWithoutPublicFetch() async throws {
        let document = try CatalogDocument.fixture()
        let local = FakeLocalCatalogStore(states: [.success([document])])
        let publicStore = FakePublicCatalogStore(states: [.offline])
        let coordinator = CatalogCoordinator(local: local, publicStore: publicStore)
        let result = await coordinator.load(identifiers: [document.identifier])
        #expect(result.state == .ready)
        #expect(result.documents == [document])
        #expect((await publicStore.receivedQueries).isEmpty)
    }

    @Test func offlineWarmLaunchKeepsStaleLocalData() async throws {
        let document = try CatalogDocument.fixture()
        let local = FakeLocalCatalogStore(states: [.stale([document])])
        let publicStore = FakePublicCatalogStore(states: [.offline])
        let coordinator = CatalogCoordinator(local: local, publicStore: publicStore)
        let result = await coordinator.load(identifiers: [document.identifier, "missing"])
        #expect(result.state == .stale)
        #expect(result.documents.map(\.identifier) == [document.identifier])
        #expect(result.failedIdentifiers == ["missing"])
    }

    @Test func refreshRechecksPublicAndPreservesLocalOnPartialResult() async throws {
        let localDocument = try CatalogDocument.fixture(contentHash: "old-hash")
        let publicDocument = try CatalogDocument.fixture(contentHash: "new-hash")
        let local = FakeLocalCatalogStore(states: [.success([localDocument]), .success([localDocument])])
        let publicStore = FakePublicCatalogStore(states: [.success([publicDocument])])
        let coordinator = CatalogCoordinator(local: local, publicStore: publicStore)

        let first = await coordinator.load(identifiers: [localDocument.identifier])
        #expect(first.documents.first?.contentHash == "old-hash")
        let refreshed = await coordinator.refresh(identifiers: [localDocument.identifier])
        #expect(refreshed.state == .ready)
        #expect(refreshed.documents.first?.contentHash == "new-hash")
        #expect((await publicStore.receivedQueries).count == 1)
        #expect((await local.replacements).count == 1)
    }

    @Test func identicalConcurrentLoadsAreCoalescedByIdentifierSet() async throws {
        let document = try CatalogDocument.fixture()
        let local = FakeLocalCatalogStore(states: [.empty])
        let publicStore = DelayedPublicStore(document: document)
        let coordinator = CatalogCoordinator(local: local, publicStore: publicStore)
        let results = await withTaskGroup(of: CatalogCoordinatorSnapshot.self, returning: [CatalogCoordinatorSnapshot].self) { group in
            for _ in 0..<3 { group.addTask { await coordinator.load(identifiers: [document.identifier]) } }
            var values: [CatalogCoordinatorSnapshot] = []
            for await value in group { values.append(value) }
            return values
        }
        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.documents == [document] })
        #expect(await publicStore.callCount == 1)
    }
}

private actor DelayedPublicStore: PublicCatalogStore {
    let document: CatalogDocument
    private(set) var callCount = 0

    init(document: CatalogDocument) { self.document = document }

    func fetch(_ query: CatalogQuery) async throws -> ServiceResponse<[CatalogDocument]> {
        callCount += 1
        try await Task.sleep(for: .milliseconds(20))
        return ServiceResponse(value: [document])
    }
}
