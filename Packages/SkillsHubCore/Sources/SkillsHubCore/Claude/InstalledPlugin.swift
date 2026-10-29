import Foundation

public enum PluginScope: String, LenientEnum, Sendable, Hashable {
    case user, project, local, managed, session, synced, unknown
}

/// One installation of a plugin, as `claude plugin list --json` reports it.
public struct InstalledPlugin: Decodable, Sendable, Hashable, Identifiable {
    public var id: String { "\(pluginID)|\(scope.rawValue)|\(projectPath ?? "")" }
    /// `name@marketplace`.
    public let pluginID: String
    public let version: String
    public let scope: PluginScope
    public let enabled: Bool
    public let installPath: String?
    public let installedAt: String?
    public let lastUpdated: String?
    public let projectPath: String?
    public let errors: [String]
    /// The commit installed, from `installed_plugins.json`. The CLI's list doesn't include it.
    public var gitCommitSha: String?

    public var marketplace: String? {
        pluginID.split(separator: "@", maxSplits: 1).dropFirst().first.map(String.init)
    }

    public init(pluginID: String, version: String, scope: PluginScope, enabled: Bool, installPath: String? = nil,
                installedAt: String? = nil, lastUpdated: String? = nil, projectPath: String? = nil,
                errors: [String] = [], gitCommitSha: String? = nil) {
        self.pluginID = pluginID
        self.version = version
        self.scope = scope
        self.enabled = enabled
        self.installPath = installPath
        self.installedAt = installedAt
        self.lastUpdated = lastUpdated
        self.projectPath = projectPath
        self.errors = errors
        self.gitCommitSha = gitCommitSha
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pluginID = try c.decode(String.self, forKey: .id)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "unknown"
        scope = try c.decodeIfPresent(PluginScope.self, forKey: .scope) ?? .unknown
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        installPath = try c.decodeIfPresent(String.self, forKey: .installPath)
        installedAt = try c.decodeIfPresent(String.self, forKey: .installedAt)
        lastUpdated = try c.decodeIfPresent(String.self, forKey: .lastUpdated)
        projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath)
        errors = try c.decodeIfPresent([String].self, forKey: .errors) ?? []
        gitCommitSha = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, scope, enabled, installPath, installedAt, lastUpdated, projectPath, errors
    }
}

/// Reads `installed_plugins.json` directly. Its format isn't documented, so this is used only
/// for the installed commit, and to list plugins when `claude` can't be run.
public struct PluginRecordsReader: Sendable {
    public struct Record: Sendable, Hashable {
        public let pluginID: String
        public let scope: PluginScope
        public let version: String?
        public let installPath: String?
        public let projectPath: String?
        public let gitCommitSha: String?
    }

    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func records() -> [Record] {
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = root["plugins"] as? [String: Any]
        else { return [] }
        var records: [Record] = []
        for (id, value) in plugins {
            for entry in (value as? [[String: Any]]) ?? [] {
                records.append(Record(
                    pluginID: id,
                    scope: PluginScope(rawValue: entry["scope"] as? String ?? "") ?? .unknown,
                    version: entry["version"] as? String,
                    installPath: entry["installPath"] as? String,
                    projectPath: entry["projectPath"] as? String,
                    gitCommitSha: entry["gitCommitSha"] as? String
                ))
            }
        }
        return records.sorted { ($0.pluginID, $0.scope.rawValue) < ($1.pluginID, $1.scope.rawValue) }
    }

    /// Installed plugins from the records alone, for when the CLI isn't available. Whether a
    /// plugin is enabled lives in settings files, so it's reported as unknown (`false`).
    public func installedPlugins() -> [InstalledPlugin] {
        records().map {
            InstalledPlugin(pluginID: $0.pluginID, version: $0.version ?? "unknown", scope: $0.scope, enabled: false,
                            installPath: $0.installPath, projectPath: $0.projectPath, gitCommitSha: $0.gitCommitSha)
        }
    }
}
