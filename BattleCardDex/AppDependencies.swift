import Foundation
import SwiftData

struct AppDependencies: Sendable {
    let catalog: CatalogCoordinator
    let images: URLSessionImageRepository

    init(container: ModelContainer, configuration: AppConfiguration) {
        let local = SwiftDataLocalCatalogStore(container: container)
        let remote = PublicCloudKitCatalogStore(configuration: configuration.cloudCatalog)
        catalog = CatalogCoordinator(local: local, publicStore: remote)
        images = URLSessionImageRepository(configuration: configuration.cache, session: URLSessionImageRepository.configuredSession(cache: configuration.cache))
    }
}
