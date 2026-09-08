import Foundation

public enum LoaderRecordField: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case date(Date)
    case data(Data)
    case strings([String])
    case integers([Int64])
}

public struct LoaderRecord: Equatable, Sendable {
    public let identifier: String
    public let recordType: String
    public let contentHash: String
    public let payload: Data
    public let fields: [String: LoaderRecordField]
    public let isManifest: Bool

    public init(identifier: String, recordType: String = "", contentHash: String, payload: Data,
                fields: [String: LoaderRecordField] = [:], isManifest: Bool = false) {
        self.identifier = identifier
        self.recordType = recordType
        self.contentHash = contentHash
        self.payload = payload
        self.fields = fields
        self.isManifest = isManifest
    }
}

public struct CloudKitServerCredentials: Equatable, Sendable {
    public let keyID: String
    public let privateKeyPath: URL

    public init(keyID: String, privateKeyPath: URL) { self.keyID = keyID; self.privateKeyPath = privateKeyPath }

    public func validate(fileManager: FileManager = .default) throws {
        guard !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CloudKitPublisherError.invalidCredentials }
        guard privateKeyPath.isFileURL, privateKeyPath.path.hasPrefix("/") else { throw CloudKitPublisherError.invalidCredentials }
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: privateKeyPath.path, isDirectory: &directory), !directory.boolValue else {
            throw CloudKitPublisherError.invalidCredentials
        }
    }
}

public protocol LoaderCloudKitService: Sendable {
    func existingHashes(for identifiers: [String]) async throws -> [String: String]
    func save(_ records: [LoaderRecord]) async throws
}

public enum CloudKitPublisherError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidCredentials
    case emptyRecordIdentifier
    case partialBatchFailure([String])
    case checkpointFailure

    public var description: String {
        switch self {
        case .invalidCredentials: "invalid CloudKit server credentials"
        case .emptyRecordIdentifier: "record identifier is empty"
        case let .partialBatchFailure(ids): "partial batch failure (\(ids.count) records)"
        case .checkpointFailure: "checkpoint could not be saved"
        }
    }
}

public protocol LoaderCheckpointStore: Sendable {
    func load() async throws -> LoaderCheckpoint
    func save(_ checkpoint: LoaderCheckpoint) async throws
}

public struct LoaderCheckpoint: Codable, Equatable, Sendable {
    public var committedRecordIDs: Set<String>
    public var manifestCommitted: Bool

    public init(committedRecordIDs: Set<String> = [], manifestCommitted: Bool = false) {
        self.committedRecordIDs = committedRecordIDs
        self.manifestCommitted = manifestCommitted
    }
}

public actor InMemoryLoaderCheckpointStore: LoaderCheckpointStore {
    private var checkpoint: LoaderCheckpoint
    public init(_ checkpoint: LoaderCheckpoint = .init()) { self.checkpoint = checkpoint }
    public func load() async throws -> LoaderCheckpoint { checkpoint }
    public func save(_ checkpoint: LoaderCheckpoint) async throws { self.checkpoint = checkpoint }
}

public struct LoaderPublishReport: Equatable, Sendable {
    public let writtenRecordIDs: [String]
    public let skippedRecordIDs: [String]
    public let manifestWritten: Bool

    public init(writtenRecordIDs: [String], skippedRecordIDs: [String], manifestWritten: Bool) {
        self.writtenRecordIDs = writtenRecordIDs
        self.skippedRecordIDs = skippedRecordIDs
        self.manifestWritten = manifestWritten
    }
}

/// Idempotent, resumable publisher. The manifest is always the final write so a
/// failed data batch cannot expose a partial catalog revision.
public struct CatalogPublisher: Sendable {
    public let credentials: CloudKitServerCredentials
    public let batchSize: Int

    public init(credentials: CloudKitServerCredentials, batchSize: Int = 100) {
        self.credentials = credentials
        self.batchSize = max(1, batchSize)
    }

    public func publish(records: [LoaderRecord], manifest: LoaderRecord, service: any LoaderCloudKitService,
                        checkpointStore: any LoaderCheckpointStore) async throws -> LoaderPublishReport {
        try credentials.validate()
        guard !manifest.identifier.isEmpty, manifest.isManifest else { throw CloudKitPublisherError.emptyRecordIdentifier }
        guard records.allSatisfy({ !$0.identifier.isEmpty && !$0.isManifest }) else { throw CloudKitPublisherError.emptyRecordIdentifier }
        var checkpoint = try await checkpointStore.load()
        let hashes = try await service.existingHashes(for: records.map(\.identifier))
        let candidates = records.filter { hashes[$0.identifier] != $0.contentHash && !checkpoint.committedRecordIDs.contains($0.identifier) }
        var written: [String] = []
        let skipped = records.filter { !candidates.contains($0) }.map(\.identifier).sorted()
        for offset in stride(from: 0, to: candidates.count, by: batchSize) {
            let end = min(offset + batchSize, candidates.count)
            let batch = Array(candidates[offset..<end])
            do {
                try await service.save(batch)
                written.append(contentsOf: batch.map(\.identifier))
                checkpoint.committedRecordIDs.formUnion(batch.map(\.identifier))
            } catch let error as CloudKitPublisherError {
                guard case let .partialBatchFailure(failedIDs) = error, batch.count > 1 else { throw error }
                // Retry only the failed records individually; successful records
                // are not rewritten and remain checkpointed on the next save.
                for record in batch where failedIDs.contains(record.identifier) {
                    try await service.save([record])
                    written.append(record.identifier)
                    checkpoint.committedRecordIDs.insert(record.identifier)
                }
            }
            do { try await checkpointStore.save(checkpoint) } catch { throw CloudKitPublisherError.checkpointFailure }
        }
        if !checkpoint.manifestCommitted {
            try await service.save([manifest])
            checkpoint.manifestCommitted = true
            do { try await checkpointStore.save(checkpoint) } catch { throw CloudKitPublisherError.checkpointFailure }
        }
        return LoaderPublishReport(writtenRecordIDs: written.sorted(), skippedRecordIDs: skipped, manifestWritten: true)
    }

    /// Publishes a self-contained slice without advancing the catalog manifest.
    /// Full-catalog synchronization uses this after each creature finishes so
    /// an interruption never discards already downloaded and uploaded work.
    public func publishData(records: [LoaderRecord], service: any LoaderCloudKitService) async throws -> LoaderPublishReport {
        try credentials.validate()
        guard records.allSatisfy({ !$0.identifier.isEmpty && !$0.isManifest }) else {
            throw CloudKitPublisherError.emptyRecordIdentifier
        }
        let hashes = try await service.existingHashes(for: records.map(\.identifier))
        let candidates = records.filter { hashes[$0.identifier] != $0.contentHash }
        let skipped = records.filter { hashes[$0.identifier] == $0.contentHash }.map(\.identifier).sorted()
        var written: [String] = []
        for offset in stride(from: 0, to: candidates.count, by: batchSize) {
            let batch = Array(candidates[offset..<min(offset + batchSize, candidates.count)])
            try await service.save(batch)
            written.append(contentsOf: batch.map(\.identifier))
        }
        return .init(writtenRecordIDs: written.sorted(), skippedRecordIDs: skipped, manifestWritten: false)
    }

    public func publishManifest(_ manifest: LoaderRecord, service: any LoaderCloudKitService) async throws {
        try credentials.validate()
        guard !manifest.identifier.isEmpty, manifest.isManifest else { throw CloudKitPublisherError.emptyRecordIdentifier }
        let hashes = try await service.existingHashes(for: [manifest.identifier])
        if hashes[manifest.identifier] != manifest.contentHash { try await service.save([manifest]) }
    }
}
