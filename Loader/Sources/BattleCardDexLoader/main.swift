import Foundation
import BattleCardDexLoaderCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let arguments = Array(CommandLine.arguments.dropFirst())
func repositoryRoot(startingAt start: URL) -> URL {
    var candidate = start.standardizedFileURL
    while true {
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".git").path) { return candidate }
        let parent = candidate.deletingLastPathComponent()
        if parent.path == candidate.path { return start }
        candidate = parent
    }
}

do {
    let command = try LoaderCommand.parse(arguments)
    let root = repositoryRoot(startingAt: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
    let resolver = LoaderSecretResolver(localEnvURL: root.appendingPathComponent(LoaderSecretResolver.localFileName), repositoryRoot: root)
    let secrets = try resolver.resolve()
    let runner = LoaderRunner(configuration: LoaderConfiguration(repositoryRoot: root, secrets: secrets))
    let transport = CachingLoaderTransport(directory: root.appendingPathComponent(".loader-cache", isDirectory: true))
    let report = await runner.runLive(command, transport: transport)
    print(try LoaderReportEncoder.encode(report))
    #if canImport(Darwin)
    Darwin.exit(Int32(report.exitCode))
    #else
    Glibc.exit(Int32(report.exitCode))
    #endif
} catch let error as LoaderCommandError {
    let report = LoaderRunReport(command: arguments.first ?? "", status: "failed", exitCode: .usage,
                                 startedAt: Date(), finishedAt: Date(), errorCode: error.description)
    print(try! LoaderReportEncoder.encode(report))
    #if canImport(Darwin)
    Darwin.exit(Int32(LoaderExitCode.usage.rawValue))
    #else
    Glibc.exit(Int32(LoaderExitCode.usage.rawValue))
    #endif
} catch let error as LoaderPreflightError {
    let report = LoaderRunReport(command: arguments.first ?? "", status: "failed", exitCode: .preflight,
                                 startedAt: Date(), finishedAt: Date(), errorCode: error.code)
    print(try! LoaderReportEncoder.encode(report))
    #if canImport(Darwin)
    Darwin.exit(Int32(LoaderExitCode.preflight.rawValue))
    #else
    Glibc.exit(Int32(LoaderExitCode.preflight.rawValue))
    #endif
} catch {
    let report = LoaderRunReport(command: arguments.first ?? "", status: "failed", exitCode: .runtime,
                                 startedAt: Date(), finishedAt: Date(), errorCode: "runtime_error")
    print(try! LoaderReportEncoder.encode(report))
    #if canImport(Darwin)
    Darwin.exit(Int32(LoaderExitCode.runtime.rawValue))
    #else
    Glibc.exit(Int32(LoaderExitCode.runtime.rawValue))
    #endif
}
