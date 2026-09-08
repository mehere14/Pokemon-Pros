import Foundation

enum AppEnvironment: String, CaseIterable, Equatable, Sendable {
    case debug
    case test
    case release
}

enum LocalPersistenceMode: Equatable, Sendable {
    case persistent
    case inMemory
}

struct FeatureFlags: Equatable, Sendable {
    let fullCatalogEnabled: Bool
    let diagnosticLoggingEnabled: Bool
    let motionEnabled: Bool
}

enum ConfigurationValidationError: Error, Equatable {
    case invalidTimeout(TimeInterval)
    case invalidRetryLimit(Int)
    case invalidPageSize(Int)
    case invalidCacheSize(Int)
    case memoryCacheExceedsDiskCache
    case invalidPrefetchDistance(Int)
    case invalidBatchSize(Int)
    case unsupportedSchemaVersion(Int)
    case emptyIdentifier
    case invalidSeedRange(ClosedRange<Int>)
    case testEnvironmentMustUseInMemoryPersistence
    case testEnvironmentMustUseFakeCloudCatalog
    case releaseEnvironmentCannotEnableDiagnostics
}

struct AppConfiguration: Equatable, Sendable {
    let environment: AppEnvironment
    let cloudCatalog: CloudCatalogConfiguration
    let cache: CacheConfiguration
    let interaction: InteractionConstants
    let motion: MotionConstants
    let design: DesignConstants
    let requestTimeout: TimeInterval
    let resourceTimeout: TimeInterval
    let maximumRetryCount: Int
    let creaturePageSize: Int
    let cardPageSize: Int
    let initialSeedRange: ClosedRange<Int>
    let defaultLocaleIdentifier: String
    let featureFlags: FeatureFlags
    let localPersistenceMode: LocalPersistenceMode

    init(
        environment: AppEnvironment,
        cloudCatalog: CloudCatalogConfiguration,
        cache: CacheConfiguration,
        interaction: InteractionConstants = .standard,
        motion: MotionConstants = .standard,
        design: DesignConstants = .standard,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        maximumRetryCount: Int,
        creaturePageSize: Int,
        cardPageSize: Int,
        initialSeedRange: ClosedRange<Int>,
        defaultLocaleIdentifier: String,
        featureFlags: FeatureFlags,
        localPersistenceMode: LocalPersistenceMode
    ) throws {
        guard requestTimeout >= 0 else {
            throw ConfigurationValidationError.invalidTimeout(requestTimeout)
        }
        guard resourceTimeout >= 0 else {
            throw ConfigurationValidationError.invalidTimeout(resourceTimeout)
        }
        guard maximumRetryCount >= 0 else {
            throw ConfigurationValidationError.invalidRetryLimit(maximumRetryCount)
        }
        guard creaturePageSize > 0 else {
            throw ConfigurationValidationError.invalidPageSize(creaturePageSize)
        }
        guard cardPageSize > 0 else {
            throw ConfigurationValidationError.invalidPageSize(cardPageSize)
        }
        guard initialSeedRange.lowerBound > 0 else {
            throw ConfigurationValidationError.invalidSeedRange(initialSeedRange)
        }
        guard !defaultLocaleIdentifier.isEmpty else {
            throw ConfigurationValidationError.emptyIdentifier
        }
        if environment == .test && localPersistenceMode != .inMemory {
            throw ConfigurationValidationError.testEnvironmentMustUseInMemoryPersistence
        }
        if environment == .test && cloudCatalog.service != .fake {
            throw ConfigurationValidationError.testEnvironmentMustUseFakeCloudCatalog
        }
        if environment == .release && featureFlags.diagnosticLoggingEnabled {
            throw ConfigurationValidationError.releaseEnvironmentCannotEnableDiagnostics
        }

        self.environment = environment
        self.cloudCatalog = cloudCatalog
        self.cache = cache
        self.interaction = interaction
        self.motion = motion
        self.design = design
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.maximumRetryCount = maximumRetryCount
        self.creaturePageSize = creaturePageSize
        self.cardPageSize = cardPageSize
        self.initialSeedRange = initialSeedRange
        self.defaultLocaleIdentifier = defaultLocaleIdentifier
        self.featureFlags = featureFlags
        self.localPersistenceMode = localPersistenceMode
    }

    static func configuration(for environment: AppEnvironment) throws -> AppConfiguration {
        let service: CloudCatalogService
        let persistence: LocalPersistenceMode
        let flags: FeatureFlags

        switch environment {
        case .debug:
            service = .developmentPublicDatabase
            persistence = .persistent
            flags = FeatureFlags(
                fullCatalogEnabled: false,
                diagnosticLoggingEnabled: true,
                motionEnabled: true
            )
        case .test:
            service = .fake
            persistence = .inMemory
            flags = FeatureFlags(
                fullCatalogEnabled: false,
                diagnosticLoggingEnabled: false,
                motionEnabled: false
            )
        case .release:
            service = .productionPublicDatabase
            persistence = .persistent
            flags = FeatureFlags(
                fullCatalogEnabled: false,
                diagnosticLoggingEnabled: false,
                motionEnabled: true
            )
        }

        return try AppConfiguration(
            environment: environment,
            cloudCatalog: CloudCatalogConfiguration(
                containerIdentifier: "iCloud.com.askcruit.Battle-Card-Dex",
                manifestRecordType: "CatalogManifest",
                creatureRecordType: "CreatureCatalogRecord",
                evolutionRecordType: "EvolutionCatalogRecord",
                cardRecordType: "CardCatalogRecord",
                schemaVersion: 1,
                // Must match the deterministic manifest name published by the
                // Development-only loader and validated by CatalogManifestRecordCodec.
                manifestRecordIdentifier: "catalog-manifest-v1",
                readBatchSize: 100,
                service: service
            ),
            cache: CacheConfiguration(
                memoryBudgetBytes: 32 * 1_024 * 1_024,
                diskBudgetBytes: 256 * 1_024 * 1_024,
                prefetchDistance: 4,
                localWriteBatchSize: 100
            ),
            requestTimeout: 15,
            resourceTimeout: 60,
            maximumRetryCount: 3,
            creaturePageSize: 60,
            cardPageSize: 250,
            initialSeedRange: 1...30,
            defaultLocaleIdentifier: "en_US_POSIX",
            featureFlags: flags,
            localPersistenceMode: persistence
        )
    }

    static let current: AppConfiguration = {
#if DEBUG
        try! configuration(for: .debug)
#else
        try! configuration(for: .release)
#endif
    }()
}
