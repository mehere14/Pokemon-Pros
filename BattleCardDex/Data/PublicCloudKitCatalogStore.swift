import CloudKit
import Foundation
import OSLog

/// Read-only client boundary for the public catalog. No save, modify, or delete
/// operation is exposed to application features.
actor PublicCloudKitCatalogStore: PublicCatalogStore, PublicCatalogQueryStore {
    private nonisolated static let logger = Logger(
        subsystem: "com.askcruit.Battle-Card-Dex",
        category: "PublicCloudKitCatalogStore"
    )
    private let database: CKDatabase
    private let configuration: CloudCatalogConfiguration
    private let maximumAttempts: Int

    init(configuration: CloudCatalogConfiguration, container: CKContainer? = nil, maximumAttempts: Int = 3) {
        self.configuration = configuration
        let resolvedContainer = container ?? CKContainer(identifier: configuration.containerIdentifier)
        self.database = resolvedContainer.publicCloudDatabase
        self.maximumAttempts = max(1, maximumAttempts)
    }

    func fetch(_ query: CatalogQuery) async throws -> ServiceResponse<[CatalogDocument]> {
        let identifiers = Array(Set(query.identifiers)).sorted()
        guard !identifiers.isEmpty else { return ServiceResponse(value: []) }
        var documents: [CatalogDocument] = []
        var failed: [String] = []
        for batch in identifiers.chunked(into: configuration.readBatchSize) {
            Self.logger.info("Fetching CloudKit batch of \(batch.count, privacy: .public) records")
            let records = try await fetchRecords(named: batch)
            for identifier in batch {
                guard let result = records[CKRecord.ID(recordName: identifier)] else {
                    failed.append(identifier)
                    continue
                }
                switch result {
                case .success(let record):
                    do {
                        documents.append(try document(from: record))
                    } catch {
                        Self.logger.error("Could not decode \(identifier, privacy: .public): \(String(reflecting: error), privacy: .public)")
#if DEBUG
                        print("BattleCardDex catalog: could not decode \(identifier): \(String(reflecting: error))")
#endif
                        throw error
                    }
                case .failure(let error):
                    let mapped = map(error)
                    if case .notFound = mapped {
                        Self.logger.notice("CloudKit record was not found: \(identifier, privacy: .public)")
                        failed.append(identifier)
                    } else {
                        Self.logger.error("CloudKit record failed: \(identifier, privacy: .public), \(String(reflecting: error), privacy: .public)")
#if DEBUG
                        print("BattleCardDex catalog: CloudKit record failed: \(identifier): \(String(reflecting: error))")
#endif
                        throw mapped
                    }
                }
            }
        }
        return ServiceResponse(value: documents.sorted { $0.identifier < $1.identifier }, failedIdentifiers: failed)
    }

    func fetchAll(recordType: String) async throws -> ServiceResponse<[CatalogDocument]> {
        let allowed = [CloudCatalogRecordContract.RecordType.card, CloudCatalogRecordContract.RecordType.evolution]
        guard allowed.contains(recordType) else { throw CatalogServiceError.malformed("unsupported_query_type") }
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var documents: [CatalogDocument] = []
        var page = try await database.records(matching: query, desiredKeys: Self.catalogRecordFields, resultsLimit: 200)
        while true {
            for (_, result) in page.matchResults {
                switch result {
                case .success(let record): documents.append(try document(from: record))
                case .failure(let error): throw map(error)
                }
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: Self.catalogRecordFields, resultsLimit: 200)
        }
        return ServiceResponse(value: documents.sorted { $0.identifier < $1.identifier })
    }

    /// Fetches a bounded batch with only the fields the record codecs validate.
    /// This keeps the first-30 catalog's initial 1,082 records from becoming
    /// 1,082 serialized CloudKit operations.
    private func fetchRecords(named names: [String]) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        var attempt = 0
        while true {
            do {
                return try await database.records(
                    for: names.map { CKRecord.ID(recordName: $0) },
                    desiredKeys: Self.catalogRecordFields
                )
            } catch {
                let mapped = map(error)
                Self.logger.error("CloudKit batch attempt \(attempt + 1, privacy: .public) failed: \(String(reflecting: error), privacy: .public)")
#if DEBUG
                print("BattleCardDex catalog: CloudKit batch attempt \(attempt + 1) failed: \(String(reflecting: error))")
#endif
                if case let .throttled(retryAfter) = mapped, attempt + 1 < maximumAttempts {
                    try await Task.sleep(for: .seconds(retryAfter))
                    attempt += 1
                    continue
                }
                if attempt + 1 < maximumAttempts, case .offline = mapped {
                    try await Task.sleep(for: .milliseconds(150 * (attempt + 1)))
                    attempt += 1
                    continue
                }
                throw mapped
            }
        }
    }

    private static let catalogRecordFields: [CKRecord.FieldKey] = [
        CloudCatalogRecordContract.Field.schemaVersion,
        CloudCatalogRecordContract.Field.sourceIdentifier,
        CloudCatalogRecordContract.Field.contentHash,
        CloudCatalogRecordContract.Field.loaderTimestamp,
        CloudCatalogRecordContract.Field.sourceTimestamp,
        CloudCatalogRecordContract.Field.payload,
        CloudCatalogRecordContract.Field.revision,
        CloudCatalogRecordContract.Field.publishedAt,
        CloudCatalogRecordContract.Field.creatureCount,
        CloudCatalogRecordContract.Field.evolutionCount,
        CloudCatalogRecordContract.Field.cardCount,
        CloudCatalogRecordContract.Field.normalizedName,
        CloudCatalogRecordContract.Field.displayName,
        CloudCatalogRecordContract.Field.generation,
        CloudCatalogRecordContract.Field.types,
        CloudCatalogRecordContract.Field.memberIdentifiers,
        CloudCatalogRecordContract.Field.setIdentifier,
        CloudCatalogRecordContract.Field.collectorNumber,
        CloudCatalogRecordContract.Field.relatedCreatureIdentifiers,
    ]

    private func document(from record: CKRecord) throws -> CatalogDocument {
        let snapshot = try CloudCatalogRecordSnapshot(record: record)
        switch snapshot.recordType {
        case CloudCatalogRecordContract.RecordType.manifest: _ = try CatalogManifestRecordCodec.decode(snapshot)
        case CloudCatalogRecordContract.RecordType.creature: _ = try CreatureCatalogRecordCodec.decode(snapshot)
        case CloudCatalogRecordContract.RecordType.evolution: _ = try EvolutionCatalogRecordCodec.decode(snapshot)
        case CloudCatalogRecordContract.RecordType.card: _ = try CardCatalogRecordCodec.decode(snapshot)
        default: throw CatalogServiceError.malformed("unsupported_record_type")
        }
        guard case let .data(payload)? = snapshot.value(for: CloudCatalogRecordContract.Field.payload),
              case let .string(hash)? = snapshot.value(for: CloudCatalogRecordContract.Field.contentHash) else {
            throw CatalogServiceError.malformed("missing_payload")
        }
        let envelope = try CatalogPersistenceEnvelope.validatingPersistedBytes(payload)
        return try CatalogDocument(identifier: record.recordID.recordName, envelope: envelope, contentHash: hash)
    }

    private func map(_ error: Error) -> CatalogServiceError {
        if let error = error as? CKError {
            switch error.code {
            case .unknownItem: return .notFound(error.localizedDescription)
            case .notAuthenticated, .networkFailure, .networkUnavailable, .serviceUnavailable: return .offline
            case .requestRateLimited, .zoneBusy:
                return .throttled(retryAfter: error.retryAfterSeconds ?? 1)
            case .operationCancelled: return .cancelled
            default: return .unavailable
            }
        }
        if error is CancellationError { return .cancelled }
        return .unavailable
    }
}

nonisolated private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { offset in
            Array(self[offset..<Swift.min(offset + size, count)])
        }
    }
}
