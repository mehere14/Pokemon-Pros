import Foundation
import SwiftData

@Model
final class CachedCatalogManifest {
    @Attribute(.unique) var sourceID: String
    var recordIdentifier: String
    var revision: Int
    var contentHash: String
    var schemaVersion: Int
    var cachedAt: Date
    var sourceUpdatedAt: Date
    var encodedPayload: Data

    init(sourceID: String, recordIdentifier: String, revision: Int, contentHash: String, schemaVersion: Int, cachedAt: Date, sourceUpdatedAt: Date, encodedPayload: Data) {
        self.sourceID = sourceID; self.recordIdentifier = recordIdentifier; self.revision = revision; self.contentHash = contentHash
        self.schemaVersion = schemaVersion; self.cachedAt = cachedAt
        self.sourceUpdatedAt = sourceUpdatedAt; self.encodedPayload = encodedPayload
    }
}

@Model
final class CachedCreature {
    @Attribute(.unique) var sourceID: Int
    var recordIdentifier: String
    var sortIndex: Int
    var normalizedName: String
    var displayName: String
    var generation: String?
    var typeIndex: String
    var contentHash: String
    var schemaVersion: Int
    var cachedAt: Date
    var encodedPayload: Data

    init(sourceID: Int, recordIdentifier: String, sortIndex: Int, normalizedName: String, displayName: String, generation: String?, typeIndex: String, contentHash: String, schemaVersion: Int, cachedAt: Date, encodedPayload: Data) {
        self.sourceID = sourceID; self.recordIdentifier = recordIdentifier; self.sortIndex = sortIndex
        self.normalizedName = normalizedName; self.displayName = displayName; self.generation = generation
        self.typeIndex = typeIndex; self.contentHash = contentHash; self.schemaVersion = schemaVersion
        self.cachedAt = cachedAt; self.encodedPayload = encodedPayload
    }
}

@Model
final class CachedEvolutionChain {
    @Attribute(.unique) var sourceID: Int
    var recordIdentifier: String
    var memberIDIndex: String
    var contentHash: String
    var schemaVersion: Int
    var cachedAt: Date
    var encodedPayload: Data

    init(sourceID: Int, recordIdentifier: String, memberIDIndex: String, contentHash: String, schemaVersion: Int, cachedAt: Date, encodedPayload: Data) {
        self.sourceID = sourceID; self.recordIdentifier = recordIdentifier; self.memberIDIndex = memberIDIndex
        self.contentHash = contentHash; self.schemaVersion = schemaVersion; self.cachedAt = cachedAt
        self.encodedPayload = encodedPayload
    }
}

@Model
final class CachedCard {
    @Attribute(.unique) var sourceID: String
    var recordIdentifier: String
    var normalizedName: String
    var collectorNumber: String
    var setID: String
    var relatedCreatureIDIndex: String
    var contentHash: String
    var schemaVersion: Int
    var cachedAt: Date
    var encodedPayload: Data

    init(sourceID: String, recordIdentifier: String, normalizedName: String, collectorNumber: String, setID: String, relatedCreatureIDIndex: String, contentHash: String, schemaVersion: Int, cachedAt: Date, encodedPayload: Data) {
        self.sourceID = sourceID; self.recordIdentifier = recordIdentifier; self.normalizedName = normalizedName
        self.collectorNumber = collectorNumber; self.setID = setID; self.relatedCreatureIDIndex = relatedCreatureIDIndex
        self.contentHash = contentHash; self.schemaVersion = schemaVersion; self.cachedAt = cachedAt
        self.encodedPayload = encodedPayload
    }
}

enum LocalCatalogContainer {
    static let schema = Schema([
        CachedCatalogManifest.self, CachedCreature.self, CachedEvolutionChain.self, CachedCard.self,
    ])

    static func make(isStoredInMemoryOnly: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration("LocalCatalog", schema: schema, url: url, cloudKitDatabase: .none)
        } else if isStoredInMemoryOnly {
            configuration = ModelConfiguration(
                "LocalCatalog", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
        } else {
            let fileManager = FileManager.default
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
            let storeURL = applicationSupport.appendingPathComponent("LocalCatalog.store", isDirectory: false)
            configuration = ModelConfiguration("LocalCatalog", schema: schema, url: storeURL, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func deleteStore(at url: URL, fileManager: FileManager = .default) throws {
        for target in [url, URL(fileURLWithPath: url.path + "-shm"), URL(fileURLWithPath: url.path + "-wal")] {
            guard fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.removeItem(at: target)
        }
    }
}
