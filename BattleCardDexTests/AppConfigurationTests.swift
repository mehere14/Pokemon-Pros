import Testing
@testable import Battle_Card_Dex

struct AppConfigurationTests {
    @Test func debugEnvironmentHasDevelopmentServices() throws {
        let configuration = try AppConfiguration.configuration(for: .debug)

        #expect(configuration.environment == .debug)
        #expect(configuration.cloudCatalog.service == .developmentPublicDatabase)
        #expect(configuration.localPersistenceMode == .persistent)
        #expect(configuration.featureFlags.diagnosticLoggingEnabled)
        #expect(configuration.featureFlags.motionEnabled)
        #expect(!configuration.featureFlags.fullCatalogEnabled)
        expectSharedValues(configuration)
    }

    @Test func testEnvironmentIsFullyIsolated() throws {
        let configuration = try AppConfiguration.configuration(for: .test)

        #expect(configuration.environment == .test)
        #expect(configuration.cloudCatalog.service == .fake)
        #expect(configuration.localPersistenceMode == .inMemory)
        #expect(!configuration.featureFlags.diagnosticLoggingEnabled)
        #expect(!configuration.featureFlags.motionEnabled)
        #expect(!configuration.featureFlags.fullCatalogEnabled)
        expectSharedValues(configuration)
    }

    @Test func releaseEnvironmentHasProductionReadServices() throws {
        let configuration = try AppConfiguration.configuration(for: .release)

        #expect(configuration.environment == .release)
        #expect(configuration.cloudCatalog.service == .productionPublicDatabase)
        #expect(configuration.localPersistenceMode == .persistent)
        #expect(!configuration.featureFlags.diagnosticLoggingEnabled)
        #expect(configuration.featureFlags.motionEnabled)
        #expect(!configuration.featureFlags.fullCatalogEnabled)
        expectSharedValues(configuration)
    }

    @Test func everyDeclaredEnvironmentBuildsAValidProfile() throws {
        for environment in AppEnvironment.allCases {
            #expect(try AppConfiguration.configuration(for: environment).environment == environment)
        }
    }

    @Test func interactionConstantsMatchApprovedBehavior() {
        let constants = InteractionConstants.standard

        #expect(constants.carouselCommitFraction == 0.22)
        #expect(constants.carouselFingerTravelMultiplier == 0.82)
        #expect(constants.carouselMaximumScaleReduction == 0.06)
        #expect(constants.flickMaximumDuration == 0.280)
        #expect(constants.flickMinimumDistance == 34)
        #expect(constants.panelOpenFraction == 0.22)
        #expect(constants.panelCloseFraction == 0.12)
        #expect(constants.panelProgressTravelFraction == 0.42)
    }

    @Test func motionConstantsIncludeReducedMotionAlternative() {
        let constants = MotionConstants.standard

        #expect(constants.carouselDuration == 0.460)
        #expect(constants.panelDuration == 0.420)
        #expect(constants.shuffleDuration == 0.480)
        #expect(constants.reducedMotionDuration == 0.001)
        #expect(constants.standardCurve.firstControlPoint.x == 0.22)
        #expect(constants.panelCurve.firstControlPoint.y == 0.9)
    }

    @Test func designConstantsMatchTheDesignAuthority() {
        let constants = DesignConstants.standard

        #expect(constants.spacing.base == 8)
        #expect(constants.spacing.phoneMargin == 16)
        #expect(constants.spacing.largeLayoutMargin == 64)
        #expect(constants.shape.standardRadius == 8)
        #expect(constants.shape.extraLargeRadius == 24)
        #expect(constants.shadow.modalBlurRadius == 40)
        #expect(constants.layout.phonePortraitColumns == 2)
        #expect(constants.layout.largeLayoutColumns == 3)
        #expect(constants.typography.displayFamily == "Sora")
        #expect(constants.palette.primary == DesignColor(red: 247, green: 230, blue: 26))
    }

    @Test func zeroAndNegativeCacheBudgetsFailValidation() {
        #expect(throws: ConfigurationValidationError.invalidCacheSize(0)) {
            try CacheConfiguration(
                memoryBudgetBytes: 0,
                diskBudgetBytes: 1,
                prefetchDistance: 0,
                localWriteBatchSize: 1
            )
        }
        #expect(throws: ConfigurationValidationError.invalidCacheSize(-1)) {
            try CacheConfiguration(
                memoryBudgetBytes: 1,
                diskBudgetBytes: -1,
                prefetchDistance: 0,
                localWriteBatchSize: 1
            )
        }
        #expect(throws: ConfigurationValidationError.memoryCacheExceedsDiskCache) {
            try CacheConfiguration(
                memoryBudgetBytes: 2,
                diskBudgetBytes: 1,
                prefetchDistance: 0,
                localWriteBatchSize: 1
            )
        }
    }

    @Test func negativeTimeoutsFailValidation() throws {
        #expect(throws: ConfigurationValidationError.invalidTimeout(-0.1)) {
            try makeConfiguration(requestTimeout: -0.1)
        }
        #expect(throws: ConfigurationValidationError.invalidTimeout(-2)) {
            try makeConfiguration(resourceTimeout: -2)
        }
    }

    @Test func unsupportedSchemaVersionsFailValidation() {
        for version in [0, 2, 99] {
            #expect(throws: ConfigurationValidationError.unsupportedSchemaVersion(version)) {
                try makeCloudConfiguration(schemaVersion: version)
            }
        }
    }

    @Test func testEnvironmentRejectsLiveCloudAndPersistentStorage() throws {
        #expect(throws: ConfigurationValidationError.testEnvironmentMustUseFakeCloudCatalog) {
            try makeConfiguration(
                environment: .test,
                cloudService: .developmentPublicDatabase,
                persistence: .inMemory
            )
        }
        #expect(throws: ConfigurationValidationError.testEnvironmentMustUseInMemoryPersistence) {
            try makeConfiguration(
                environment: .test,
                cloudService: .fake,
                persistence: .persistent
            )
        }
    }

    @Test func releaseEnvironmentRejectsDiagnosticLogging() throws {
        #expect(throws: ConfigurationValidationError.releaseEnvironmentCannotEnableDiagnostics) {
            try makeConfiguration(
                environment: .release,
                cloudService: .productionPublicDatabase,
                diagnosticLoggingEnabled: true
            )
        }
    }

    private func expectSharedValues(_ configuration: AppConfiguration) {
        #expect(configuration.cloudCatalog.containerIdentifier == "iCloud.com.askcruit.Battle-Card-Dex")
        #expect(configuration.cloudCatalog.manifestRecordType == "CatalogManifest")
        #expect(configuration.cloudCatalog.creatureRecordType == "CreatureCatalogRecord")
        #expect(configuration.cloudCatalog.evolutionRecordType == "EvolutionCatalogRecord")
        #expect(configuration.cloudCatalog.cardRecordType == "CardCatalogRecord")
        #expect(configuration.cloudCatalog.schemaVersion == 1)
        #expect(configuration.cloudCatalog.manifestRecordIdentifier == "catalog-manifest-v1")
        #expect(configuration.cloudCatalog.readBatchSize == 100)
        #expect(configuration.cache.memoryBudgetBytes == 32 * 1_024 * 1_024)
        #expect(configuration.cache.diskBudgetBytes == 256 * 1_024 * 1_024)
        #expect(configuration.cache.prefetchDistance == 4)
        #expect(configuration.cache.localWriteBatchSize == 100)
        #expect(configuration.requestTimeout == 15)
        #expect(configuration.resourceTimeout == 60)
        #expect(configuration.maximumRetryCount == 3)
        #expect(configuration.creaturePageSize == 60)
        #expect(configuration.cardPageSize == 250)
        #expect(configuration.initialSeedRange == (1...30))
        #expect(configuration.defaultLocaleIdentifier == "en_US_POSIX")
    }

    private func makeCloudConfiguration(
        schemaVersion: Int = 1,
        service: CloudCatalogService = .fake
    ) throws -> CloudCatalogConfiguration {
        try CloudCatalogConfiguration(
            containerIdentifier: "test.container",
            manifestRecordType: "Manifest",
            creatureRecordType: "Creature",
            evolutionRecordType: "Evolution",
            cardRecordType: "Card",
            schemaVersion: schemaVersion,
            manifestRecordIdentifier: "manifest-v1",
            readBatchSize: 1,
            service: service
        )
    }

    private func makeConfiguration(
        environment: AppEnvironment = .test,
        requestTimeout: Double = 1,
        resourceTimeout: Double = 1,
        cloudService: CloudCatalogService = .fake,
        persistence: LocalPersistenceMode = .inMemory,
        diagnosticLoggingEnabled: Bool = false
    ) throws -> AppConfiguration {
        try AppConfiguration(
            environment: environment,
            cloudCatalog: makeCloudConfiguration(service: cloudService),
            cache: CacheConfiguration(
                memoryBudgetBytes: 1,
                diskBudgetBytes: 1,
                prefetchDistance: 0,
                localWriteBatchSize: 1
            ),
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout,
            maximumRetryCount: 0,
            creaturePageSize: 1,
            cardPageSize: 1,
            initialSeedRange: 1...1,
            defaultLocaleIdentifier: "en_US_POSIX",
            featureFlags: FeatureFlags(
                fullCatalogEnabled: false,
                diagnosticLoggingEnabled: diagnosticLoggingEnabled,
                motionEnabled: false
            ),
            localPersistenceMode: persistence
        )
    }
}
