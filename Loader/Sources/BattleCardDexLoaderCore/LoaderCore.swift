import Foundation
#if canImport(Security)
import Security
#endif

public enum LoaderExitCode: Int, Sendable {
    case success = 0
    case usage = 2
    case preflight = 3
    case validation = 4
    case runtime = 5
}

public struct IndexRange: Equatable, Codable, Sendable, CustomStringConvertible {
    public let lowerBound: Int
    public let upperBound: Int

    public init(lowerBound: Int, upperBound: Int) throws {
        guard lowerBound > 0, upperBound >= lowerBound else {
            throw LoaderCommandError.invalidRange("\(lowerBound)...\(upperBound)")
        }
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public var description: String { "\(lowerBound)...\(upperBound)" }
    public var count: Int { upperBound - lowerBound + 1 }
}

public enum LoaderCommand: Equatable, Sendable {
    case seed(range: IndexRange)
    case sync(range: IndexRange)
    case syncAll
    case validate
    case dryRun(range: IndexRange?)
    case effectAudit(range: IndexRange, output: String)

    public var name: String {
        switch self {
        case .seed: "seed"
        case .sync: "sync"
        case .syncAll: "sync --all"
        case .validate: "validate"
        case .dryRun: "dry-run"
        case .effectAudit: "effect-audit"
        }
    }

    public var range: IndexRange? {
        switch self {
        case let .seed(range), let .sync(range): range
        case let .dryRun(range): range
        case let .effectAudit(range, _): range
        default: nil
        }
    }

    public var requiresSecrets: Bool {
        switch self {
        // Live validation is a signed, read-only CloudKit Web Services query.
        // It needs the same external server-to-server credentials as a loader
        // publication, but has no records/modify operation.
        case .seed, .sync, .syncAll, .validate: true
        case .dryRun, .effectAudit: false
        }
    }

    public static func parse(_ arguments: [String]) throws -> LoaderCommand {
        guard let first = arguments.first else { throw LoaderCommandError.missingCommand }
        switch first {
        case "seed":
            guard arguments.count == 3, arguments[1] == "--range" else {
                throw LoaderCommandError.invalidArguments("seed requires --range LOWER...UPPER")
            }
            return .seed(range: try parseRange(arguments[2]))
        case "sync":
            if arguments.count == 2, arguments[1] == "--all" { return .syncAll }
            guard arguments.count == 3, arguments[1] == "--range" else {
                throw LoaderCommandError.invalidArguments("sync requires --range LOWER...UPPER or --all")
            }
            return .sync(range: try parseRange(arguments[2]))
        case "validate":
            guard arguments.count == 1 else { throw LoaderCommandError.invalidArguments("validate takes no arguments") }
            return .validate
        case "dry-run":
            if arguments.count == 1 { return .dryRun(range: nil) }
            guard arguments.count == 3, arguments[1] == "--range" else {
                throw LoaderCommandError.invalidArguments("dry-run accepts --range LOWER...UPPER")
            }
            return .dryRun(range: try parseRange(arguments[2]))
        case "effect-audit":
            guard arguments.count == 5, arguments[1] == "--range", arguments[3] == "--output" else {
                throw LoaderCommandError.invalidArguments("effect-audit requires --range LOWER...UPPER --output DIRECTORY")
            }
            return .effectAudit(range: try parseRange(arguments[2]), output: arguments[4])
        default:
            throw LoaderCommandError.unknownCommand(first)
        }
    }

    private static func parseRange(_ value: String) throws -> IndexRange {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[1].isEmpty, parts[2].isEmpty, parts[3].isEmpty == false,
              let lower = Int(parts[0]), let upper = Int(parts[3]) else {
            throw LoaderCommandError.invalidRange(value)
        }
        return try IndexRange(lowerBound: lower, upperBound: upper)
    }
}

public enum LoaderCommandError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingCommand
    case unknownCommand(String)
    case invalidArguments(String)
    case invalidRange(String)

    public var description: String {
        switch self {
        case .missingCommand: "missing command"
        case let .unknownCommand(command): "unknown command: \(command)"
        case let .invalidArguments(message): message
        case let .invalidRange(value): "invalid range: \(value); expected LOWER...UPPER with positive indexes"
        }
    }
}

public enum LoaderSecretKey: String, CaseIterable, Hashable, Sendable {
    case cardSourceAPIKey = "BATTLE_CARD_DEX_CARD_SOURCE_API_KEY"
    case cloudKitKeyID = "BATTLE_CARD_DEX_CLOUDKIT_KEY_ID"
    case cloudKitPrivateKeyPath = "BATTLE_CARD_DEX_CLOUDKIT_PRIVATE_KEY_PATH"
}

public struct LoaderSecrets: Equatable, Sendable {
    public let cardSourceAPIKey: String?
    public let cloudKitKeyID: String?
    public let cloudKitPrivateKeyPath: String?

    public init(cardSourceAPIKey: String? = nil, cloudKitKeyID: String? = nil, cloudKitPrivateKeyPath: String? = nil) {
        self.cardSourceAPIKey = Self.cleaned(cardSourceAPIKey)
        self.cloudKitKeyID = Self.cleaned(cloudKitKeyID)
        self.cloudKitPrivateKeyPath = Self.cleaned(cloudKitPrivateKeyPath)
    }

    public func missingRequiredValues(for command: LoaderCommand) -> [LoaderSecretKey] {
        guard command.requiresSecrets else { return [] }
        return [
            cloudKitKeyID == nil ? .cloudKitKeyID : nil,
            cloudKitPrivateKeyPath == nil ? .cloudKitPrivateKeyPath : nil
        ].compactMap { $0 }
    }

    public func redactedDescription() -> [String: String] {
        var result: [String: String] = [:]
        if cardSourceAPIKey != nil { result[LoaderSecretKey.cardSourceAPIKey.rawValue] = "[REDACTED]" }
        if cloudKitKeyID != nil { result[LoaderSecretKey.cloudKitKeyID.rawValue] = "[REDACTED]" }
        if cloudKitPrivateKeyPath != nil { result[LoaderSecretKey.cloudKitPrivateKeyPath.rawValue] = "[REDACTED_PATH]" }
        return result
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol SecretStore: Sendable {
    func value(for key: LoaderSecretKey, service: String) -> String?
}

public struct EmptySecretStore: SecretStore {
    public init() {}
    public func value(for key: LoaderSecretKey, service: String) -> String? { nil }
}

/// Reads generic-password entries without ever exporting secret material to disk.
public struct KeychainSecretStore: SecretStore {
    public init() {}

    public func value(for key: LoaderSecretKey, service: String) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }
}

public struct LoaderSecretResolver: Sendable {
    public static let service = "com.askcruit.Battle-Card-Dex.loader"
    public static let localFileName = ".env.local"

    private let environment: [String: String]
    private let localEnvURL: URL?
    private let keychain: any SecretStore
    private let repositoryRoot: URL?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                localEnvURL: URL? = nil,
                keychain: any SecretStore = EmptySecretStore(),
                repositoryRoot: URL? = nil) {
        self.environment = environment
        self.localEnvURL = localEnvURL
        self.keychain = keychain
        self.repositoryRoot = repositoryRoot
    }

    public func resolve() throws -> LoaderSecrets {
        let local = try localValues()
        func value(_ key: LoaderSecretKey) -> String? {
            if let fromEnvironment = environment[key.rawValue] {
                let trimmed = fromEnvironment.trimmingCharacters(in: .whitespacesAndNewlines)
                // An explicitly empty environment value means “not configured.” This
                // lets optional credentials avoid an unnecessary Keychain lookup.
                return trimmed.isEmpty ? nil : fromEnvironment
            }
            if let fromLocal = local[key.rawValue], !fromLocal.isEmpty { return fromLocal }
            return keychain.value(for: key, service: Self.service)
        }
        return LoaderSecrets(
            cardSourceAPIKey: value(.cardSourceAPIKey),
            cloudKitKeyID: value(.cloudKitKeyID),
            cloudKitPrivateKeyPath: value(.cloudKitPrivateKeyPath)
        )
    }

    private func localValues() throws -> [String: String] {
        guard let localEnvURL, FileManager.default.fileExists(atPath: localEnvURL.path) else { return [:] }
        #if canImport(Darwin)
        let attributes = try FileManager.default.attributesOfItem(atPath: localEnvURL.path)
        if let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 != 0 {
            throw LoaderPreflightError.insecureEnvFile(localEnvURL.path)
        }
        #endif
        let text = try String(contentsOf: localEnvURL, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).reduce(into: [:]) { result, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { return }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard LoaderSecretKey(rawValue: key) != nil else { return }
            result[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }
}

public struct LoaderConfiguration: Equatable, Sendable {
    public let environmentName: String
    public let repositoryRoot: URL?
    public let secrets: LoaderSecrets

    public init(environmentName: String = "Development", repositoryRoot: URL? = nil, secrets: LoaderSecrets) {
        self.environmentName = environmentName
        self.repositoryRoot = repositoryRoot
        self.secrets = secrets
    }

    public func validate(for command: LoaderCommand, fileManager: FileManager = .default) throws {
        let missing = secrets.missingRequiredValues(for: command)
        guard missing.isEmpty else { throw LoaderPreflightError.missingSecrets(missing) }
        guard command.requiresSecrets, let path = secrets.cloudKitPrivateKeyPath else { return }
        let keyURL = URL(fileURLWithPath: path)
        guard keyURL.path.hasPrefix("/") else { throw LoaderPreflightError.privateKeyPathMustBeAbsolute }
        if let repositoryRoot, keyURL.standardizedFileURL.path.hasPrefix(repositoryRoot.standardizedFileURL.path + "/") {
            throw LoaderPreflightError.privateKeyInsideRepository
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: keyURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw LoaderPreflightError.privateKeyNotFound(keyURL.path)
        }
    }
}

public enum LoaderPreflightError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingSecrets([LoaderSecretKey])
    case insecureEnvFile(String)
    case privateKeyPathMustBeAbsolute
    case privateKeyInsideRepository
    case privateKeyNotFound(String)

    public var code: String {
        switch self {
        case let .missingSecrets(keys): "missing_secrets_" + keys.map(\.rawValue).joined(separator: "_")
        case .insecureEnvFile: "insecure_env_file"
        case .privateKeyPathMustBeAbsolute: "private_key_path_not_absolute"
        case .privateKeyInsideRepository: "private_key_inside_repository"
        case .privateKeyNotFound: "private_key_not_found"
        }
    }

    public var description: String {
        switch self {
        case let .missingSecrets(keys): "missing required loader secret(s): " + keys.map(\.rawValue).joined(separator: ", ")
        case let .insecureEnvFile(path): "refusing insecure local env file (permissions must be owner-only): \(path)"
        case .privateKeyPathMustBeAbsolute: "CloudKit private-key path must be absolute"
        case .privateKeyInsideRepository: "CloudKit private-key path must be outside the repository"
        case let .privateKeyNotFound(path): "CloudKit private-key file was not found: \(path)"
        }
    }
}

public enum LoaderExecutionError: Error, Equatable, CustomStringConvertible, Sendable {
    case pipelineNotConfigured

    public var description: String {
        "catalog execution pipeline is not configured; use dry-run/validate or provide the provider and CloudKit adapters"
    }
}

public struct LoaderRunReport: Codable, Equatable, Sendable {
    public let command: String
    public let status: String
    public let exitCode: Int
    public let startedAt: Date
    public let finishedAt: Date
    public let range: String?
    public let recordCounts: [String: Int]
    public let errorCode: String?

    public init(command: String, status: String, exitCode: LoaderExitCode, startedAt: Date, finishedAt: Date,
                range: String? = nil, recordCounts: [String: Int] = [:], errorCode: String? = nil) {
        self.command = command
        self.status = status
        self.exitCode = exitCode.rawValue
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.range = range
        self.recordCounts = recordCounts
        self.errorCode = errorCode
    }
}

public struct LoaderRunner: Sendable {
    public let configuration: LoaderConfiguration
    public let now: @Sendable () -> Date

    public init(configuration: LoaderConfiguration, now: @escaping @Sendable () -> Date = Date.init) {
        self.configuration = configuration
        self.now = now
    }

    public func run(_ command: LoaderCommand) -> LoaderRunReport {
        let started = now()
        do {
            try configuration.validate(for: command)
            let status: String
            switch command {
            case .validate: status = "validated"
            case .dryRun: status = "dry-run"
            case .effectAudit: status = "audit-ready"
            case .seed, .sync, .syncAll: throw LoaderExecutionError.pipelineNotConfigured
            }
            return LoaderRunReport(command: command.name, status: status, exitCode: .success,
                                   startedAt: started, finishedAt: now(), range: command.range?.description,
                                   recordCounts: [:])
        } catch let error as LoaderPreflightError {
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .preflight,
                                   startedAt: started, finishedAt: now(), range: command.range?.description,
                                   errorCode: error.code)
        } catch let error as LoaderExecutionError {
            return LoaderRunReport(command: command.name, status: "blocked", exitCode: .runtime,
                                   startedAt: started, finishedAt: now(), range: command.range?.description,
                                   errorCode: error == .pipelineNotConfigured ? "pipeline_not_configured" : "execution_error")
        } catch {
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .runtime,
                                   startedAt: started, finishedAt: now(), range: command.range?.description,
                                   errorCode: "runtime_error")
        }
    }

    public func runLive(_ command: LoaderCommand, transport: any LoaderTransport = URLSessionLoaderTransport()) async -> LoaderRunReport {
        let started = now()
        do {
            try configuration.validate(for: command)
            switch command {
            case .validate:
                guard let root = configuration.repositoryRoot,
                      let keyID = configuration.secrets.cloudKitKeyID,
                      let keyPath = configuration.secrets.cloudKitPrivateKeyPath else {
                    throw LoaderExecutionError.pipelineNotConfigured
                }
                let pipelineConfiguration = LoaderPipelineConfiguration(
                    checkpointURL: root.appendingPathComponent(".loader-state/validate-read-only.json")
                )
                let credentials = CloudKitServerCredentials(keyID: keyID, privateKeyPath: URL(fileURLWithPath: keyPath))
                let webConfiguration = try CloudKitWebServiceConfiguration(containerIdentifier: pipelineConfiguration.containerIdentifier)
                let service = CloudKitWebService(configuration: webConfiguration, transport: transport,
                                                 signer: CloudKitRequestSigner(credentials: credentials, now: now))
                let validation = try await DevelopmentCatalogValidator().validate(service: service)
                return LoaderRunReport(command: command.name, status: "validated", exitCode: .success,
                                       startedAt: started, finishedAt: now(), range: "1...30",
                                       recordCounts: validation.recordCounts)
            case let .dryRun(range):
                guard let range else {
                    return LoaderRunReport(command: command.name, status: "dry-run", exitCode: .success,
                                           startedAt: started, finishedAt: now())
                }
                guard let root = configuration.repositoryRoot else { throw LoaderExecutionError.pipelineNotConfigured }
                let pipelineConfiguration = LoaderPipelineConfiguration(checkpointURL: root.appendingPathComponent(".loader-state/dry-run-\(range.description).json"))
                let batch = try await LiveCatalogPipeline(configuration: pipelineConfiguration, transport: transport,
                                                          cardAPIKey: configuration.secrets.cardSourceAPIKey, now: now).build(range: range)
                return LoaderRunReport(command: command.name, status: "dry-run", exitCode: .success,
                                       startedAt: started, finishedAt: now(), range: range.description, recordCounts: batch.counts)
            case let .effectAudit(range, output):
                guard let root = configuration.repositoryRoot else { throw LoaderExecutionError.pipelineNotConfigured }
                let outputURL = URL(fileURLWithPath: output, relativeTo: root).standardizedFileURL
                let audit = CardEffectCoverageAudit(transport: transport, cardAPIKey: configuration.secrets.cardSourceAPIKey)
                let report = try await audit.run(range: range)
                try CardEffectCoverageReportWriter.write(report, to: outputURL)
                return LoaderRunReport(command: command.name, status: "audited", exitCode: .success,
                                       startedAt: started, finishedAt: now(), range: range.description,
                                       recordCounts: report.counts)
            case .syncAll:
                guard let root = configuration.repositoryRoot,
                      let keyID = configuration.secrets.cloudKitKeyID,
                      let keyPath = configuration.secrets.cloudKitPrivateKeyPath else {
                    throw LoaderExecutionError.pipelineNotConfigured
                }
                let checkpointURL = root.appendingPathComponent(".loader-state/sync-all.json")
                let pipelineConfiguration = LoaderPipelineConfiguration(checkpointURL: checkpointURL)
                let pipeline = LiveCatalogPipeline(configuration: pipelineConfiguration, transport: transport,
                                                   cardAPIKey: configuration.secrets.cardSourceAPIKey, now: now)
                let credentials = CloudKitServerCredentials(keyID: keyID, privateKeyPath: URL(fileURLWithPath: keyPath))
                let webConfiguration = try CloudKitWebServiceConfiguration(containerIdentifier: pipelineConfiguration.containerIdentifier)
                let service = CloudKitWebService(configuration: webConfiguration, transport: transport,
                                                 signer: CloudKitRequestSigner(credentials: credentials, now: now))
                let catalogSize = try await pipeline.discoverCatalogSize()
                let counts = try await FullCatalogSynchronizer(catalogSize: catalogSize).run(
                    pipeline: pipeline,
                    publisher: CatalogPublisher(credentials: credentials),
                    service: service,
                    checkpointStore: FullCatalogSyncCheckpointStore(fileURL: checkpointURL)
                )
                return LoaderRunReport(command: command.name, status: "published", exitCode: .success,
                                       startedAt: started, finishedAt: now(), range: "1...\(catalogSize)", recordCounts: counts)
            case let .seed(range), let .sync(range):
                guard let root = configuration.repositoryRoot,
                      let keyID = configuration.secrets.cloudKitKeyID,
                      let keyPath = configuration.secrets.cloudKitPrivateKeyPath else {
                    throw LoaderExecutionError.pipelineNotConfigured
                }
                let checkpointURL = root.appendingPathComponent(".loader-state/\(command.name)-\(range.description).json")
                let pipelineConfiguration = LoaderPipelineConfiguration(checkpointURL: checkpointURL)
                let pipeline = LiveCatalogPipeline(configuration: pipelineConfiguration, transport: transport,
                                                   cardAPIKey: configuration.secrets.cardSourceAPIKey, now: now)
                let batch = try await pipeline.build(range: range)
                let credentials = CloudKitServerCredentials(keyID: keyID, privateKeyPath: URL(fileURLWithPath: keyPath))
                let webConfiguration = try CloudKitWebServiceConfiguration(containerIdentifier: pipelineConfiguration.containerIdentifier)
                let service = CloudKitWebService(configuration: webConfiguration, transport: transport,
                                                 signer: CloudKitRequestSigner(credentials: credentials, now: now))
                let report = try await CatalogPublisher(credentials: credentials).publish(
                    records: batch.records, manifest: batch.manifest, service: service,
                    checkpointStore: FileLoaderCheckpointStore(fileURL: checkpointURL)
                )
                var counts = batch.counts
                counts["written"] = report.writtenRecordIDs.count
                counts["skipped"] = report.skippedRecordIDs.count
                return LoaderRunReport(command: command.name, status: "published", exitCode: .success,
                                       startedAt: started, finishedAt: now(), range: range.description, recordCounts: counts)
            }
        } catch let error as LoaderPreflightError {
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .preflight,
                                   startedAt: started, finishedAt: now(), range: command.range?.description, errorCode: error.code)
        } catch let error as CatalogPipelineError {
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .validation,
                                   startedAt: started, finishedAt: now(), range: command.range?.description,
                                   errorCode: "catalog_\(String(describing: error))")
        } catch let error as CatalogValidationError {
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .validation,
                                   startedAt: started, finishedAt: now(), range: "1...30", errorCode: error.code)
        } catch let error as CloudKitWebServiceError {
            let code: String
            switch error {
            case let .httpStatus(status): code = "cloudkit_http_\(status)"
            case let .server(serverCode, _, reason):
                let detail = reason?.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }.reduce(into: "") { $0.append($1) }
                    .prefix(96) ?? Substring()
                code = "cloudkit_server_\(serverCode.lowercased())" + (detail.isEmpty ? "" : "_\(detail)")
            case .invalidPrivateKey: code = "cloudkit_invalid_private_key"
            case .invalidResponse: code = "cloudkit_invalid_response"
            case .unsafeConfiguration: code = "cloudkit_unsafe_configuration"
            }
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .runtime,
                                   startedAt: started, finishedAt: now(), range: command.range?.description, errorCode: code)
        } catch let error as CloudKitPublisherError {
            let code: String
            switch error {
            case .invalidCredentials: code = "publisher_invalid_credentials"
            case .emptyRecordIdentifier: code = "publisher_invalid_record"
            case let .partialBatchFailure(ids): code = "publisher_partial_failure_\(ids.count)"
            case .checkpointFailure: code = "publisher_checkpoint_failure"
            }
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .runtime,
                                   startedAt: started, finishedAt: now(), range: command.range?.description, errorCode: code)
        } catch let error as LoaderHTTPError {
            let code: String
            switch error {
            case let .httpStatus(status, _): code = "provider_http_\(status)"
            case .invalidURL: code = "provider_invalid_url"
            case .malformedResponse: code = "provider_malformed_response"
            case .duplicateCursor: code = "provider_duplicate_cursor"
            case .missingNextCursor: code = "provider_missing_cursor"
            }
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .runtime,
                                   startedAt: started, finishedAt: now(), range: command.range?.description, errorCode: code)
        } catch let error as URLError {
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .runtime,
                                   startedAt: started, finishedAt: now(), range: command.range?.description,
                                   errorCode: "network_\(error.code.rawValue)")
        } catch {
            return LoaderRunReport(command: command.name, status: "failed", exitCode: .runtime,
                                   startedAt: started, finishedAt: now(), range: command.range?.description,
                                   errorCode: "runtime_error")
        }
    }
}

public enum LoaderReportEncoder {
    public static func encode(_ report: LoaderRunReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }
}

public enum SecretRedactor {
    public static func redact(_ message: String, secrets: LoaderSecrets) -> String {
        [secrets.cardSourceAPIKey, secrets.cloudKitKeyID, secrets.cloudKitPrivateKeyPath]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .reduce(message) { $0.replacingOccurrences(of: $1, with: "[REDACTED]") }
    }
}
