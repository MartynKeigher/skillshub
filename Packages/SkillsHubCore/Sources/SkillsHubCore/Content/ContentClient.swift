import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A file in a repository at a fixed commit, as the index lists it.
public struct RemoteFile: Sendable, Hashable {
    public let repo: String
    public let commit: String
    /// Path from the repository root.
    public let path: String
    public let size: Int64
    /// Git blob SHA-1 from the index, when it has one.
    public let sha: String?

    public init(repo: String, commit: String, path: String, size: Int64, sha: String?) {
        self.repo = repo
        self.commit = commit
        self.path = path
        self.size = size
        self.sha = sha
    }

    var rawURL: URL {
        let parts = repo.split(separator: "/").map(String.init) + [commit] + path.split(separator: "/").map(String.init)
        let segments = parts.map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? $0
        }
        return URL(string: "https://raw.githubusercontent.com/" + segments.joined(separator: "/"))!
    }
}

public enum ContentError: LocalizedError, Equatable {
    case http(Int)
    case hashMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case let .http(status):
            "GitHub returned HTTP \(status) for this file."
        case .hashMismatch:
            "This file doesn't match the catalog: its contents changed or the download was altered."
        }
    }
}

/// Fetches the contents of skill and plugin files, so people can read every file before installing.
public protocol ContentClientProtocol: Sendable {
    func contents(of file: RemoteFile) async throws -> Data
}

/// Reads files from raw.githubusercontent.com at the indexed commit. A file at a commit never
/// changes, so each is cached on disk for good, and checked against the index's hash when
/// downloaded and again when read back.
public struct ContentClient: ContentClientProtocol {
    private let session: URLSession
    private let cacheDirectory: URL?

    public init(session: URLSession = .shared, cacheDirectory: URL?) {
        self.session = session
        self.cacheDirectory = cacheDirectory
    }

    public func contents(of file: RemoteFile) async throws -> Data {
        let cached = cacheURL(for: file)
        if let cached, let data = try? Data(contentsOf: cached), (try? verify(data, against: file)) != nil {
            return data
        }
        let (data, response) = try await session.data(from: file.rawURL)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw ContentError.http(http.statusCode)
        }
        try verify(data, against: file)
        if let cached {
            try? FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cached, options: .atomic)
        }
        return data
    }

    private func verify(_ data: Data, against file: RemoteFile) throws {
        guard let expected = file.sha else { return }
        let actual = GitBlobHash.of(data)
        guard actual == expected else { throw ContentError.hashMismatch(expected: expected, actual: actual) }
    }

    /// Keyed by the blob hash when known (identical files share an entry), else by repo, commit and path.
    private func cacheURL(for file: RemoteFile) -> URL? {
        guard let cacheDirectory else { return nil }
        if let sha = file.sha {
            return cacheDirectory.appendingPathComponent("blobs/\(sha.prefix(2))/\(sha)")
        }
        let safe = "\(file.repo)/\(file.commit)/\(file.path)".replacingOccurrences(of: "..", with: "_")
        return cacheDirectory.appendingPathComponent("paths").appendingPathComponent(safe)
    }
}
