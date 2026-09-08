import Foundation
import Testing
@testable import BattleCardDexLoaderCore

private actor FakeCloudKitService: LoaderCloudKitService {
    var hashes: [String: String]
    var batches: [[LoaderRecord]] = []
    var failuresRemaining: Int
    init(hashes: [String: String] = [:], failuresRemaining: Int = 0) { self.hashes = hashes; self.failuresRemaining = failuresRemaining }
    func existingHashes(for identifiers: [String]) async throws -> [String: String] { hashes.filter { identifiers.contains($0.key) } }
    func save(_ records: [LoaderRecord]) async throws {
        if failuresRemaining > 0 { failuresRemaining -= 1; throw CloudKitPublisherError.partialBatchFailure(records.map(\.identifier)) }
        batches.append(records)
        for record in records { hashes[record.identifier] = record.contentHash }
    }
}

@Test("publisher skips unchanged records and writes manifest last")
func publisherIsIdempotent() async throws {
    let key = URL(fileURLWithPath: "/private/tmp/loader-test-key.p8")
    FileManager.default.createFile(atPath: key.path, contents: Data([1]))
    defer { try? FileManager.default.removeItem(at: key) }
    let records = [LoaderRecord(identifier: "creature-1", contentHash: "new", payload: Data([1])), LoaderRecord(identifier: "creature-2", contentHash: "same", payload: Data([2]))]
    let manifest = LoaderRecord(identifier: "manifest", contentHash: "m", payload: Data([3]), isManifest: true)
    let service = FakeCloudKitService(hashes: ["creature-2": "same"])
    let checkpoint = InMemoryLoaderCheckpointStore()
    let publisher = CatalogPublisher(credentials: CloudKitServerCredentials(keyID: "id", privateKeyPath: key))
    let report = try await publisher.publish(records: records, manifest: manifest, service: service, checkpointStore: checkpoint)
    #expect(report.writtenRecordIDs == ["creature-1"])
    #expect(report.skippedRecordIDs == ["creature-2"])
    #expect(report.manifestWritten)
    #expect((await service.batches).last?.first?.isManifest == true)
}

@Test("failed data batch leaves manifest unpublished and is resumable")
func publisherFailureIsSafe() async throws {
    let key = URL(fileURLWithPath: "/private/tmp/loader-test-key-2.p8")
    FileManager.default.createFile(atPath: key.path, contents: Data([1]))
    defer { try? FileManager.default.removeItem(at: key) }
    let service = FakeCloudKitService(failuresRemaining: 1)
    let publisher = CatalogPublisher(credentials: CloudKitServerCredentials(keyID: "id", privateKeyPath: key), batchSize: 1)
    let record = LoaderRecord(identifier: "creature-1", contentHash: "h", payload: Data())
    let manifest = LoaderRecord(identifier: "manifest", contentHash: "m", payload: Data(), isManifest: true)
    await #expect(throws: CloudKitPublisherError.partialBatchFailure(["creature-1"])) {
        _ = try await publisher.publish(records: [record], manifest: manifest, service: service, checkpointStore: InMemoryLoaderCheckpointStore())
    }
    #expect((await service.batches).isEmpty)
}
