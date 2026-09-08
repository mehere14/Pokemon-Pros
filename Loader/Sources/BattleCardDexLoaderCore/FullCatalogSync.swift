import Foundation

public struct FullCatalogRecordIndexEntry: Codable, Equatable, Sendable {
    public let recordType: String
    public let contentHash: String

    public init(recordType: String, contentHash: String) {
        self.recordType = recordType
        self.contentHash = contentHash
    }
}

/// Durable journal for the streaming full-catalog job. A creature ID is only
/// committed after CloudKit has reconciled every record produced for that ID.
public struct FullCatalogSyncCheckpoint: Codable, Equatable, Sendable {
    public var catalogSize: Int
    public var completedCreatureIDs: Set<Int>
    public var recordIndex: [String: FullCatalogRecordIndexEntry]
    public var manifestCommitted: Bool
    public var indexedCreatureIDs: Set<Int>?
    public var detailIndexedCreatureIDs: Set<Int>?

    public init(catalogSize: Int, completedCreatureIDs: Set<Int> = [],
                recordIndex: [String: FullCatalogRecordIndexEntry] = [:], manifestCommitted: Bool = false,
                indexedCreatureIDs: Set<Int>? = nil, detailIndexedCreatureIDs: Set<Int>? = nil) {
        self.catalogSize = catalogSize
        self.completedCreatureIDs = completedCreatureIDs
        self.recordIndex = recordIndex
        self.manifestCommitted = manifestCommitted
        self.indexedCreatureIDs = indexedCreatureIDs
        self.detailIndexedCreatureIDs = detailIndexedCreatureIDs
    }
}

public actor FullCatalogSyncCheckpointStore {
    private let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load(catalogSize: Int) throws -> FullCatalogSyncCheckpoint {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .init(catalogSize: catalogSize)
        }
        let value = try JSONDecoder().decode(FullCatalogSyncCheckpoint.self, from: Data(contentsOf: fileURL))
        var resumed = value
        resumed.catalogSize = catalogSize
        resumed.completedCreatureIDs = resumed.completedCreatureIDs.filter { $0 <= catalogSize }
        if resumed.completedCreatureIDs.count < catalogSize { resumed.manifestCommitted = false }
        return resumed
    }

    public func save(_ value: FullCatalogSyncCheckpoint) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: fileURL, options: [.atomic])
        #if canImport(Darwin)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        #endif
    }
}

public struct FullCatalogSynchronizer: Sendable {
    public let catalogSize: Int

    public init(catalogSize: Int) { self.catalogSize = catalogSize }

    public func run(pipeline: LiveCatalogPipeline, publisher: CatalogPublisher,
                    service: any LoaderCloudKitService, checkpointStore: FullCatalogSyncCheckpointStore) async throws -> [String: Int] {
        var checkpoint = try await checkpointStore.load(catalogSize: catalogSize)
        var written = 0
        var skipped = 0

        for id in 1...catalogSize where !checkpoint.completedCreatureIDs.contains(id) || !(checkpoint.detailIndexedCreatureIDs ?? []).contains(id) {
            try Task.checkCancellation()
            let isBackfill = checkpoint.completedCreatureIDs.contains(id)
            Self.progress("[\(id)/\(catalogSize)] \(isBackfill ? "backfilling lazy-detail index" : "downloading creature bundle")")
            let batch = try await pipeline.buildCreature(index: id)
            let report = try await publisher.publishData(records: batch.records, service: service)
            written += report.writtenRecordIDs.count
            skipped += report.skippedRecordIDs.count
            for record in batch.records {
                checkpoint.recordIndex[record.identifier] = .init(recordType: record.recordType, contentHash: record.contentHash)
            }
            checkpoint.completedCreatureIDs.insert(id)
            checkpoint.indexedCreatureIDs = (checkpoint.indexedCreatureIDs ?? []).union([id])
            checkpoint.detailIndexedCreatureIDs = (checkpoint.detailIndexedCreatureIDs ?? []).union([id])
            checkpoint.manifestCommitted = false
            try await checkpointStore.save(checkpoint)

            // Publish progress only after the entire creature bundle is
            // reconciled. Clients can now discover this creature and query its
            // cards while the next bundle downloads.
            let progressManifest = try pipeline.makeManifest(recordIndex: checkpoint.recordIndex)
            try await publisher.publishManifest(progressManifest, service: service)
            checkpoint.manifestCommitted = true
            try await checkpointStore.save(checkpoint)
            Self.progress("[\(id)/\(catalogSize)] committed to CloudKit — \(batch.records.count) records, \(report.writtenRecordIDs.count) written, \(report.skippedRecordIDs.count) unchanged")
        }

        let manifest = try pipeline.makeManifest(recordIndex: checkpoint.recordIndex)
        try await publisher.publishManifest(manifest, service: service)
        checkpoint.manifestCommitted = true
        try await checkpointStore.save(checkpoint)

        return [
            "creatures": checkpoint.completedCreatureIDs.count,
            "records": checkpoint.recordIndex.count,
            "written": written,
            "skipped": skipped,
        ]
    }

    private static func progress(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
