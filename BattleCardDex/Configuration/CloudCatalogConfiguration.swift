import Foundation

enum CloudCatalogService: Equatable, Sendable {
    case developmentPublicDatabase
    case productionPublicDatabase
    case fake
}

struct CloudCatalogConfiguration: Equatable, Sendable {
    static let supportedSchemaVersions: ClosedRange<Int> = 1...1

    let containerIdentifier: String
    let manifestRecordType: String
    let creatureRecordType: String
    let evolutionRecordType: String
    let cardRecordType: String
    let schemaVersion: Int
    let manifestRecordIdentifier: String
    let readBatchSize: Int
    let service: CloudCatalogService

    init(
        containerIdentifier: String,
        manifestRecordType: String,
        creatureRecordType: String,
        evolutionRecordType: String,
        cardRecordType: String,
        schemaVersion: Int,
        manifestRecordIdentifier: String,
        readBatchSize: Int,
        service: CloudCatalogService
    ) throws {
        guard Self.supportedSchemaVersions.contains(schemaVersion) else {
            throw ConfigurationValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard readBatchSize > 0 else {
            throw ConfigurationValidationError.invalidBatchSize(readBatchSize)
        }

        let requiredIdentifiers = [
            containerIdentifier,
            manifestRecordType,
            creatureRecordType,
            evolutionRecordType,
            cardRecordType,
            manifestRecordIdentifier,
        ]
        guard requiredIdentifiers.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ConfigurationValidationError.emptyIdentifier
        }

        self.containerIdentifier = containerIdentifier
        self.manifestRecordType = manifestRecordType
        self.creatureRecordType = creatureRecordType
        self.evolutionRecordType = evolutionRecordType
        self.cardRecordType = cardRecordType
        self.schemaVersion = schemaVersion
        self.manifestRecordIdentifier = manifestRecordIdentifier
        self.readBatchSize = readBatchSize
        self.service = service
    }
}
