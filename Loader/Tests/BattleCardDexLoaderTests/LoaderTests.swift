import Foundation
import Testing
@testable import BattleCardDexLoaderCore

private struct StubSecretStore: SecretStore {
    let values: [LoaderSecretKey: String]
    let onLookup: @Sendable (LoaderSecretKey, String) -> Void

    init(_ values: [LoaderSecretKey: String] = [:], onLookup: @escaping @Sendable (LoaderSecretKey, String) -> Void = { _, _ in }) {
        self.values = values
        self.onLookup = onLookup
    }

    func value(for key: LoaderSecretKey, service: String) -> String? {
        onLookup(key, service)
        return values[key]
    }
}

@Test("all loader commands parse")
func parsesCommands() throws {
    #expect(try LoaderCommand.parse(["seed", "--range", "1...30"]) == .seed(range: try IndexRange(lowerBound: 1, upperBound: 30)))
    #expect(try LoaderCommand.parse(["sync", "--range", "4...9"]) == .sync(range: try IndexRange(lowerBound: 4, upperBound: 9)))
    #expect(try LoaderCommand.parse(["sync", "--all"]) == .syncAll)
    #expect(try LoaderCommand.parse(["validate"]) == .validate)
    #expect(try LoaderCommand.parse(["dry-run"]) == .dryRun(range: nil))
    #expect(try LoaderCommand.parse(["dry-run", "--range", "1...30"]) == .dryRun(range: try IndexRange(lowerBound: 1, upperBound: 30)))
    #expect(try LoaderCommand.parse(["effect-audit", "--range", "1...30", "--output", "Documentation/effects"]) == .effectAudit(range: try IndexRange(lowerBound: 1, upperBound: 30), output: "Documentation/effects"))
}

@Test("effect audit joins explicit finishes without retaining prices")
func effectAuditClassification() throws {
    let provider = ProviderEffectCard(id: "set-a-1", name: "Sample Card", setID: "set-a", number: "1",
                                      rarity: "Rare Holo", subtypes: ["Basic"], finishes: [.holo])
    let enriched = TCGdexEffectCard(id: "set-a-1", name: "Sample Card", localID: "1", setID: "set-a",
                                    rarity: "Rare Holo", category: "Creature", stage: "Basic", suffix: nil,
                                    finishes: [.holo, .reverseHolo], foilPattern: "cosmos")
    let entry = CardEffectCoverageEngine().classify(provider, enriched: enriched)
    #expect(entry.confidence == .exact)
    #expect(entry.family == .cosmosHolo)
    #expect(entry.mask == .artworkWindow)
    #expect(entry.finishes == [.holo, .reverseHolo])
    let encoded = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self).lowercased()
    #expect(!encoded.contains("market"))
    #expect(!encoded.contains("price"))
}

@Test("effect audit rejects conflicting fallback identity")
func effectAuditConflict() {
    let provider = ProviderEffectCard(id: "provider-1", name: "Expected", setID: "set-a", number: "1", rarity: nil, subtypes: [], finishes: [])
    let enriched = TCGdexEffectCard(id: "different-1", name: "Other", localID: "2", setID: "set-b", rarity: nil, category: nil, stage: nil, suffix: nil, finishes: [])
    let entry = CardEffectCoverageEngine().classify(provider, enriched: enriched)
    #expect(entry.confidence == .ambiguous)
    #expect(entry.family == .unsupported)
}

@Test("every supported effect family selects a safe generic mask")
func allEffectFamiliesHaveMasks() {
    for family in CardEffectFamily.allCases where family != .unsupported {
        #expect(CardEffectCoverageEngine.mask(for: family) != .customOverride)
    }
    #expect(CardEffectCoverageEngine.mask(for: .reverseHolo) == .outsideArtworkWindow)
    #expect(CardEffectCoverageEngine.mask(for: .radiantHolo) == .radiantBurst)
    #expect(CardEffectCoverageEngine.mask(for: .amazingRare) == .amazingBreakout)
}

@Test("effect coverage report output is deterministic and contains a markdown table")
func effectAuditReportOutput() throws {
    let entry = CardEffectAuditEntry(id: "a", name: "Card", setID: "set", number: "1", finishes: [.normal], family: .basic,
                                     mask: .specularSpot, confidence: .exact, sources: ["card-provider"], foilPattern: nil, note: nil)
    let report = CardEffectCoverageReport(generatedAt: Date(timeIntervalSince1970: 1), range: "1...1", entries: [entry])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try CardEffectCoverageReportWriter.write(report, to: directory)
    let markdown = try String(contentsOf: directory.appendingPathComponent("card-effect-coverage.md"), encoding: .utf8)
    let json = try String(contentsOf: directory.appendingPathComponent("card-effect-coverage.json"), encoding: .utf8)
    #expect(markdown.contains("| basic | 1 |"))
    #expect(json.contains("\"specularSpot\""))
}

@Test("invalid and missing ranges are rejected")
func rejectsRanges() {
    for arguments in [["seed"], ["seed", "--range"], ["seed", "--range", "0...3"], ["seed", "--range", "8...3"], ["sync", "--range", "1..3"], ["sync", "--all", "extra"]] {
        #expect(throws: Error.self) { try LoaderCommand.parse(arguments) }
    }
}

@Test("preflight fails before a network-capable run")
func missingSecretsFailPreflight() throws {
    let command = try LoaderCommand.parse(["seed", "--range", "1...3"])
    let report = LoaderRunner(configuration: LoaderConfiguration(secrets: LoaderSecrets())).run(command)
    #expect(report.exitCode == LoaderExitCode.preflight.rawValue)
    #expect(report.status == "failed")
    #expect(report.errorCode?.contains(LoaderSecretKey.cloudKitKeyID.rawValue) == true)
}

@Test("credentialed mutating commands stop until execution adapters are configured")
func mutatingCommandDoesNotPretendToPublish() throws {
    let keyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([0x2D]).write(to: keyURL)
    defer { try? FileManager.default.removeItem(at: keyURL) }
    let command = try LoaderCommand.parse(["seed", "--range", "1...3"])
    let configuration = LoaderConfiguration(
        repositoryRoot: URL(fileURLWithPath: "/private/tmp/loader-repo"),
        secrets: LoaderSecrets(cloudKitKeyID: "development-key", cloudKitPrivateKeyPath: keyURL.path)
    )
    let report = LoaderRunner(configuration: configuration).run(command)
    #expect(report.exitCode == LoaderExitCode.runtime.rawValue)
    #expect(report.status == "blocked")
    #expect(report.errorCode == "pipeline_not_configured")
}

@Test("CI environment values override Keychain without writing to disk")
func environmentOverridesKeychain() throws {
    let keyPath = "/private/tmp/cloudkit-loader-test.p8"
    let lookedUp = LockedBox<[String]>([])
    let store = StubSecretStore([
        .cardSourceAPIKey: "keychain-card",
        .cloudKitKeyID: "keychain-id",
        .cloudKitPrivateKeyPath: keyPath
    ]) { key, service in
        lookedUp.withValue { $0.append("\(service):\(key.rawValue)") }
    }
    let resolver = LoaderSecretResolver(environment: [
        LoaderSecretKey.cloudKitKeyID.rawValue: "ci-id",
        LoaderSecretKey.cloudKitPrivateKeyPath.rawValue: keyPath
    ], keychain: store)
    let secrets = try resolver.resolve()
    #expect(secrets.cloudKitKeyID == "ci-id")
    #expect(secrets.cloudKitPrivateKeyPath == keyPath)
    #expect(secrets.cardSourceAPIKey == "keychain-card")
    #expect(lookedUp.value.isEmpty == false)
    #expect(lookedUp.value.allSatisfy { $0.hasPrefix(LoaderSecretResolver.service + ":") })
    #expect(FileManager.default.fileExists(atPath: keyPath) == false)
}

@Test("local env fallback is owner-only and uses the loader service")
func localEnvFallback() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let envURL = directory.appendingPathComponent(".env.local")
    try "BATTLE_CARD_DEX_CLOUDKIT_KEY_ID=local-id\nBATTLE_CARD_DEX_CLOUDKIT_PRIVATE_KEY_PATH=/private/tmp/key.p8\n".write(to: envURL, atomically: true, encoding: .utf8)
    #if canImport(Darwin)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envURL.path)
    #endif
    let secrets = try LoaderSecretResolver(environment: [:], localEnvURL: envURL, keychain: EmptySecretStore()).resolve()
    #expect(secrets.cloudKitKeyID == "local-id")
    #expect(secrets.cloudKitPrivateKeyPath == "/private/tmp/key.p8")
}

@Test("logs redact all injected secret values")
func redactsSecrets() {
    let secrets = LoaderSecrets(cardSourceAPIKey: "card-secret", cloudKitKeyID: "cloud-secret", cloudKitPrivateKeyPath: "/private/tmp/private-secret.p8")
    let message = "card-secret cloud-secret /private/tmp/private-secret.p8"
    let redacted = SecretRedactor.redact(message, secrets: secrets)
    #expect(!redacted.contains("card-secret"))
    #expect(!redacted.contains("cloud-secret"))
    #expect(!redacted.contains("private-secret"))
    #expect(redacted.filter { $0 == "[" }.count == 3)
}

@Test("shipping project does not reference the loader target")
func loaderIsNonShipping() throws {
    let sourceFile = URL(fileURLWithPath: #filePath)
    let root = sourceFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let project = try String(contentsOf: root.appendingPathComponent("Battle Card Dex.xcodeproj/project.pbxproj"), encoding: .utf8)
    #expect(!project.contains("BattleCardDexLoader"))
    #expect(!project.contains("Loader/"))
}

@Test("ignore rules protect secrets while allowing placeholders")
func ignoreRules() throws {
    let sourceFile = URL(fileURLWithPath: #filePath)
    let root = sourceFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let rules = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
    #expect(rules.contains(".env\n"))
    #expect(rules.contains(".env.*"))
    #expect(rules.contains("!.env.example"))
    #expect(rules.contains("*.p8"))
    #expect(rules.contains("credentials/"))
    let example = try String(contentsOf: root.appendingPathComponent(".env.example"), encoding: .utf8)
    #expect(example.contains("<cloudkit-server-key-id>"))
    #expect(!example.contains("sk-"))
}

private final class LockedBox<Value>: @unchecked Sendable {
    private var storage: Value
    private let lock = NSLock()
    init(_ value: Value) { storage = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return storage }
    func withValue(_ body: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; body(&storage) }
}
