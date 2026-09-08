//
//  BattleCardDexApp.swift
//  Battle Card Dex
//
//  Created by Mihir Panchal on 2026-08-31.
//

import SwiftUI
import SwiftData

@main
@MainActor
struct BattleCardDexApp: App {
    let sharedModelContainer: ModelContainer
    @StateObject private var catalogModel: CatalogViewModel

    init() {
        let appConfiguration = AppConfiguration.current
        do {
            let container = try LocalCatalogContainer.make(
                isStoredInMemoryOnly: appConfiguration.localPersistenceMode == .inMemory
            )
            sharedModelContainer = container
            if ProcessInfo.processInfo.environment["BATTLE_CARD_DEX_USE_PREVIEW"] == "1" {
                _catalogModel = StateObject(wrappedValue: CatalogViewModel.preview())
                return
            }
            let dependencies = AppDependencies(container: container, configuration: appConfiguration)
            _catalogModel = StateObject(wrappedValue: CatalogViewModel(
                coordinator: dependencies.catalog,
                supportedRange: appConfiguration.initialSeedRange,
                manifestRecordIdentifier: appConfiguration.cloudCatalog.manifestRecordIdentifier,
                imageRepository: dependencies.images
            ))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: catalogModel)
        }
        .modelContainer(sharedModelContainer)
    }
}
