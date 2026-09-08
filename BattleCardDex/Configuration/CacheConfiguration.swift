import Foundation

nonisolated struct CacheConfiguration: Equatable, Sendable {
    let memoryBudgetBytes: Int
    let diskBudgetBytes: Int
    let prefetchDistance: Int
    let localWriteBatchSize: Int

    static let standard = try! CacheConfiguration(
        memoryBudgetBytes: 32 * 1_024 * 1_024,
        // Retained for URLSession's opportunistic HTTP cache. Successfully
        // decoded artwork also enters the unbounded persistent image store.
        diskBudgetBytes: 256 * 1_024 * 1_024,
        prefetchDistance: 4,
        localWriteBatchSize: 100
    )

    init(
        memoryBudgetBytes: Int,
        diskBudgetBytes: Int,
        prefetchDistance: Int,
        localWriteBatchSize: Int
    ) throws {
        guard memoryBudgetBytes > 0 else {
            throw ConfigurationValidationError.invalidCacheSize(memoryBudgetBytes)
        }
        guard diskBudgetBytes > 0 else {
            throw ConfigurationValidationError.invalidCacheSize(diskBudgetBytes)
        }
        guard memoryBudgetBytes <= diskBudgetBytes else {
            throw ConfigurationValidationError.memoryCacheExceedsDiskCache
        }
        guard prefetchDistance >= 0 else {
            throw ConfigurationValidationError.invalidPrefetchDistance(prefetchDistance)
        }
        guard localWriteBatchSize > 0 else {
            throw ConfigurationValidationError.invalidBatchSize(localWriteBatchSize)
        }

        self.memoryBudgetBytes = memoryBudgetBytes
        self.diskBudgetBytes = diskBudgetBytes
        self.prefetchDistance = prefetchDistance
        self.localWriteBatchSize = localWriteBatchSize
    }
}
