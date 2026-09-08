import CryptoKit
import Foundation

nonisolated enum ImageRepositoryError: Error, Equatable, Sendable {
    case invalidURL
    case httpStatus(Int)
    case corruptData
}

/// Lazy memory + permanent disk image repository. An image is fetched only when
/// a view asks for its URL; after the first successful fetch its bytes are kept
/// in Application Support with no age or size eviction policy.
actor URLSessionImageRepository: ImageRepository {
    private let session: URLSession
    private let memoryLimitBytes: Int
    private let persistentDirectory: URL
    private var memory: [URL: Data] = [:]
    private var memoryOrder: [URL] = []
    private var memoryBytes = 0
    private var inFlight: [URL: Task<Data, Error>] = [:]

    init(configuration: CacheConfiguration = .standard, session: URLSession = .shared,
         persistentDirectory: URL? = nil) {
        self.session = session
        self.memoryLimitBytes = configuration.memoryBudgetBytes
        self.persistentDirectory = persistentDirectory ?? Self.defaultPersistentDirectory()
    }

    func data(for url: URL) async throws -> ServiceResponse<Data> {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw ImageRepositoryError.invalidURL
        }
        if let cached = memory[url] { return ServiceResponse(value: cached) }
        if let cached = try? persistentData(for: url), !cached.isEmpty {
            retainInMemory(cached, for: url)
            return ServiceResponse(value: cached)
        }
        if let task = inFlight[url] { return ServiceResponse(value: try await task.value) }
        let destination = cacheURL(for: url)
        let task = Task<Data, Error> { [session, persistentDirectory] in
            let (bytes, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw ImageRepositoryError.corruptData }
            guard (200..<300).contains(http.statusCode) else { throw ImageRepositoryError.httpStatus(http.statusCode) }
            guard !bytes.isEmpty else { throw ImageRepositoryError.corruptData }
            try FileManager.default.createDirectory(at: persistentDirectory, withIntermediateDirectories: true)
            try bytes.write(to: destination, options: [.atomic])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var directory = persistentDirectory
            try? directory.setResourceValues(values)
            return bytes
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let result = try await task.value
        retainInMemory(result, for: url)
        return ServiceResponse(value: result)
    }

    /// Clears only volatile RAM. The durable offline collection intentionally
    /// survives launches and memory-pressure cleanup.
    func removeAllCachedImages() {
        memory.removeAll()
        memoryOrder.removeAll()
        memoryBytes = 0
    }

    static func configuredSession(cache: CacheConfiguration = .standard) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: cache.memoryBudgetBytes / 4,
                                          diskCapacity: cache.diskBudgetBytes,
                                          diskPath: "battle-card-dex-images")
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }

    private func persistentData(for url: URL) throws -> Data {
        try Data(contentsOf: cacheURL(for: url), options: [.mappedIfSafe])
    }

    private func cacheURL(for url: URL) -> URL {
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return persistentDirectory.appendingPathComponent(key).appendingPathExtension("image")
    }

    private func retainInMemory(_ data: Data, for url: URL) {
        if let previous = memory.updateValue(data, forKey: url) {
            memoryBytes -= previous.count
            memoryOrder.removeAll { $0 == url }
        }
        memoryBytes += data.count
        memoryOrder.append(url)
        while memoryBytes > memoryLimitBytes, let oldest = memoryOrder.first {
            memoryOrder.removeFirst()
            if let removed = memory.removeValue(forKey: oldest) { memoryBytes -= removed.count }
        }
    }

    private static func defaultPersistentDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BattleCardDex", isDirectory: true)
            .appendingPathComponent("ImageCache", isDirectory: true)
    }
}
