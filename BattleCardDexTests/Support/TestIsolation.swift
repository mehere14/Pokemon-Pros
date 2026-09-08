import Foundation
import SwiftData
@testable import Battle_Card_Dex

enum InMemoryTestStore {
    static func makeContainer() throws -> ModelContainer {
        try LocalCatalogContainer.make(isStoredInMemoryOnly: true)
    }
}

nonisolated enum TestCloudIsolationError: Error, Equatable {
    case productionAccessDenied
    case developmentEnvironmentRequired
    case emptyRunIdentifier
}

/// Creates deterministic record-name prefixes for Development integration tests.
/// The type cannot represent a Production namespace.
nonisolated struct DevelopmentCloudRecordNamespace: Equatable, Sendable {
    let prefix: String

    init(service: CloudCatalogService, runIdentifier: String) throws {
        switch service {
        case .productionPublicDatabase:
            throw TestCloudIsolationError.productionAccessDenied
        case .fake:
            throw TestCloudIsolationError.developmentEnvironmentRequired
        case .developmentPublicDatabase:
            break
        }

        let sanitized = runIdentifier
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" { result.append(character) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !sanitized.isEmpty else { throw TestCloudIsolationError.emptyRunIdentifier }
        prefix = "development-test-\(sanitized)"
    }

    func recordName(for identifier: String) -> String {
        "\(prefix)-\(identifier)"
    }
}
