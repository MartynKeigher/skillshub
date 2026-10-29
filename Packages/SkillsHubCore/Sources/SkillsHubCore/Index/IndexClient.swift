import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum IndexFetchResult: Sendable {
    case notModified
    case updated(data: Data, etag: String?)
}

/// Downloads the latest catalog. Stands in for CaskHub's `BrewAPIClient`.
public protocol IndexClientProtocol: Sendable {
    func fetchLatest(etag: String?) async throws -> IndexFetchResult
}

public struct IndexClient: IndexClientProtocol {
    public static let latestURL = URL(string: "https://github.com/MartynKeigher/skillsflow/releases/latest/download/index.json")!

    public struct HTTPError: LocalizedError {
        public let statusCode: Int
        public var errorDescription: String? { "The catalog download failed (HTTP \(statusCode))." }
    }

    private let url: URL
    private let session: URLSession

    public init(url: URL = IndexClient.latestURL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func fetchLatest(etag: String?) async throws -> IndexFetchResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return .updated(data: data, etag: nil) }
        if http.statusCode == 304 { return .notModified }
        guard (200 ..< 300).contains(http.statusCode) else { throw HTTPError(statusCode: http.statusCode) }
        return .updated(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
    }
}

/// The last downloaded catalog, kept in the app's Caches folder with its ETag and date.
public struct IndexCache: Sendable {
    public struct Metadata: Codable, Sendable, Equatable {
        public var etag: String?
        public var generatedAt: String
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    var dataURL: URL { directory.appendingPathComponent("index.json") }
    var metadataURL: URL { directory.appendingPathComponent("index.meta.json") }

    public func metadata() -> Metadata? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(Metadata.self, from: data)
    }

    public func load() -> Data? {
        try? Data(contentsOf: dataURL)
    }

    public func save(_ data: Data, metadata: Metadata) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: dataURL, options: .atomic)
        try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
    }
}

/// The catalog that ships inside the app, so it opens instantly and works offline.
public struct BundledIndex: Sendable {
    /// `generated_at` of the bundled copy, from a small file written next to it, so the app
    /// can tell whether the cache is newer without decoding the bundled copy.
    public let generatedAt: String?
    public let load: @Sendable () -> Data?

    public init(generatedAt: String?, load: @escaping @Sendable () -> Data?) {
        self.generatedAt = generatedAt
        self.load = load
    }
}
