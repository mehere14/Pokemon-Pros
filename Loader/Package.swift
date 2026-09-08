// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BattleCardDexLoader",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "battle-card-dex-loader", targets: ["BattleCardDexLoader"]),
        .library(name: "BattleCardDexLoaderCore", targets: ["BattleCardDexLoaderCore"])
    ],
    targets: [
        .target(name: "BattleCardDexLoaderCore"),
        .executableTarget(name: "BattleCardDexLoader", dependencies: ["BattleCardDexLoaderCore"]),
        .testTarget(name: "BattleCardDexLoaderTests", dependencies: ["BattleCardDexLoaderCore"])
    ]
)
