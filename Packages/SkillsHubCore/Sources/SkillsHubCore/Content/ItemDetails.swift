import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One item's file list and findings, as a detail shard holds them.
public struct ItemDetail: Decodable, Sendable, Hashable {
    public let commit: String?
    public let files: [IndexFile]
    public let findings: [Finding]

    public init(commit: String?, files: [IndexFile], findings: [Finding]) {
        self.commit = commit
        self.files = files
        self.findings = findings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commit = try c.decodeIfPresent(String.self, forKey: .commit)
        files = try c.decodeIfPresent([IndexFile].self, forKey: .files) ?? []
        findings = try c.decodeIfPresent([Finding].self, forKey: .findings) ?? []
    }

    private enum CodingKeys: String, CodingKey { case commit, files, findings }
}

struct DetailShard: Decodable, Sendable {
    let items: [String: ItemDetail]
}

public enum DetailsError: LocalizedError, Equatable {
    /// The shard isn't published anymore: the catalog is older than the releases SkillsFlow keeps.
    case gone
    /// The shard is from a different release than the catalog.
    case stale
    case missing(String)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .gone, .stale: "These details belong to an older catalog. Refresh the catalog and try again."
        case let .missing(id): "The catalog has no details for \(id)."
        case let .http(status): "Downloading the details failed (HTTP \(status))."
        }
    }
}

/// Fetches detail shards. Stands apart from the catalog so tests can supply shards directly.
public protocol DetailsClientProtocol: Sendable {
    func shard(_ bucket: String, catalog: CatalogIndex) async throws -> [String: ItemDetail]
}

/// Downloads shards from the catalog's release and caches them per catalog.
public struct DetailsClient: DetailsClientProtocol {
    static let latestTemplate = "https://github.com/MartynKeigher/skillsflow/releases/latest/download/details-{bucket}.json"

    private let session: URLSession
    private let cacheDirectory: URL?

    public init(session: URLSession = .shared, cacheDirectory: URL?) {
        self.session = session
        self.cacheDirectory = cacheDirectory
    }

    public func shard(_ bucket: String, catalog: CatalogIndex) async throws -> [String: ItemDetail] {
        let cached = cacheDirectory?.appendingPathComponent(Self.folderName(catalog.generatedAt))
            .appendingPathComponent("details-\(bucket).json")
        if let cached, let data = try? Data(contentsOf: cached), let shard = try? JSONDecoder().decode(DetailShard.self, from: data) {
            return shard.items
        }
        let template = catalog.details?.url ?? Self.latestTemplate
        guard let url = URL(string: template.replacingOccurrences(of: "{bucket}", with: bucket)) else {
            throw DetailsError.missing(bucket)
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw DetailsError.gone }
            guard (200 ..< 300).contains(http.statusCode) else { throw DetailsError.http(http.statusCode) }
        }
        let shard = try JSONDecoder().decode(DetailShard.self, from: data)
        // A shard from `latest` may belong to a newer release; only the catalog's own is kept.
        if let cached, catalog.details?.url != nil {
            try? FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cached, options: .atomic)
        }
        return shard.items
    }

    /// Removes shards cached for other catalogs.
    public func removeCaches(except catalog: CatalogIndex) {
        guard let cacheDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path) else { return }
        for name in names where name != Self.folderName(catalog.generatedAt) {
            try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(name))
        }
    }

    static func folderName(_ generatedAt: String) -> String {
        generatedAt.replacingOccurrences(of: ":", with: "-")
    }
}

/// A file of the item being shown, with where to read its contents.
public struct ItemFile: Sendable, Hashable, Identifiable {
    public var id: String { path }
    /// Path inside the item: for a plugin, skill files sit under their folder's path.
    public let path: String
    public let remote: RemoteFile
    public let kind: FileKind
    public let executable: Bool
    /// The skill this file belongs to, when the item is a plugin.
    public let skillID: String?

    public var size: Int64 { remote.size }
}

/// Everything in an item, for its contents view and the review before install.
public struct ItemDetails: Sendable, Hashable {
    public let files: [ItemFile]
    public let findings: [LocatedFinding]

    public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    public func findings(in path: String) -> [LocatedFinding] {
        findings.filter { $0.path == path }
    }
}

extension Catalog {
    /// The bucket a detail shard is keyed by: two hex digits of the SHA-1 of the item's ID.
    public static func detailBucket(for id: String) -> String {
        var sha = SHA1()
        sha.update(Data(id.utf8))
        return String(sha.hexDigest().prefix(2))
    }

    /// Loads an item's files and findings: from the catalog itself for version 1, otherwise
    /// from the shards that hold the item and, for a plugin, each of its skills.
    public func details(of item: CatalogItem, using client: any DetailsClientProtocol) async throws -> ItemDetails {
        let ids: [String]
        switch item.kind {
        case .skill: ids = [item.id]
        case .plugin: ids = [item.id] + (pluginsByID[item.id]?.skills ?? [])
        }
        let details = try await fetchDetails(ids, client: client)
        switch item.kind {
        case .skill:
            guard let skill = skillsByID[item.id], let detail = details[item.id] else { throw DetailsError.missing(item.id) }
            return ItemDetails(files: Self.files(detail.files, repo: skill.repo, root: skill.path, commit: skill.commit,
                                                 prefix: "", skillID: nil),
                               findings: detail.findings.map { LocatedFinding(finding: $0, pathPrefix: "", skillID: nil) })
        case .plugin:
            guard let plugin = pluginsByID[item.id], let repo = plugin.repo, let commit = plugin.commit,
                  let own = details[item.id] else { throw DetailsError.missing(item.id) }
            var files = Self.files(own.files, repo: repo, root: plugin.path ?? "", commit: commit, prefix: "", skillID: nil)
            var findings = own.findings.map { LocatedFinding(finding: $0, pathPrefix: "", skillID: nil) }
            for skill in skills(of: plugin) {
                guard let detail = details[skill.id] else { continue }
                let prefix = plugin.relativePath(of: skill)
                files += Self.files(detail.files, repo: skill.repo, root: skill.path, commit: skill.commit,
                                    prefix: prefix, skillID: skill.id)
                findings += detail.findings.map { LocatedFinding(finding: $0, pathPrefix: prefix, skillID: skill.id) }
            }
            return ItemDetails(files: files.sorted { $0.path < $1.path }, findings: findings)
        }
    }

    private func fetchDetails(_ ids: [String], client: any DetailsClientProtocol) async throws -> [String: ItemDetail] {
        if index.hasInlineDetails {
            var result: [String: ItemDetail] = [:]
            for id in ids {
                if let skill = skillsByID[id] {
                    result[id] = ItemDetail(commit: skill.commit, files: skill.files, findings: skill.security.findings)
                } else if let plugin = pluginsByID[id] {
                    result[id] = ItemDetail(commit: plugin.commit, files: plugin.files, findings: plugin.security?.findings ?? [])
                }
            }
            return result
        }
        let buckets = Dictionary(grouping: ids, by: Self.detailBucket)
        let index = self.index
        let shards = try await withThrowingTaskGroup(of: [String: ItemDetail].self) { group in
            for bucket in buckets.keys {
                group.addTask { try await client.shard(bucket, catalog: index) }
            }
            return try await group.reduce(into: [String: ItemDetail]()) { $0.merge($1) { first, _ in first } }
        }
        var result: [String: ItemDetail] = [:]
        for id in ids {
            guard let detail = shards[id] else { continue }
            let expected = skillsByID[id]?.commit ?? pluginsByID[id]?.commit
            // A shard from another release would describe different files than the ones installed.
            if let expected, let commit = detail.commit, commit != expected { throw DetailsError.stale }
            result[id] = detail
        }
        return result
    }

    private static func files(_ files: [IndexFile], repo: String, root: String, commit: String, prefix: String,
                              skillID: String?) -> [ItemFile] {
        files.map { file in
            ItemFile(path: prefix.isEmpty ? file.path : "\(prefix)/\(file.path)",
                     remote: RemoteFile(repo: repo, commit: commit, path: root.isEmpty ? file.path : "\(root)/\(file.path)",
                                        size: file.size, sha: file.sha),
                     kind: file.kind, executable: file.executable, skillID: skillID)
        }
    }
}
