import Foundation

// The SkillsFlow catalog: docs/index-schema.md in MartynKeigher/skillsflow. Versions 1 and 2
// both decode. Version 2 moved file lists and findings into detail shards; version 1 has them
// inline. Fields are only added within a version, so every field added after the first
// release decodes as optional, and unknown enum values decode as `.unknown`.

public struct CatalogIndex: Decodable, Sendable {
    public static let supportedSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: String
    public let generator: String?
    public let categories: [String]
    public let featured: [FeaturedPick]
    /// Where the detail shards are. Nil for a version 1 catalog, which has details inline.
    public let details: DetailsLocation?
    public let marketplaces: [IndexMarketplace]
    public let plugins: [IndexPlugin]
    public let skills: [IndexSkill]
    public let repos: [IndexRepo]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try c.decode(String.self, forKey: .generatedAt)
        generator = try c.decodeIfPresent(String.self, forKey: .generator)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        featured = try c.decodeIfPresent([FeaturedPick].self, forKey: .featured) ?? []
        details = schemaVersion >= 2 ? try c.decodeIfPresent(DetailsLocation.self, forKey: .details) : nil
        marketplaces = try c.decodeIfPresent([IndexMarketplace].self, forKey: .marketplaces) ?? []
        plugins = try c.decodeIfPresent([IndexPlugin].self, forKey: .plugins) ?? []
        skills = try c.decodeIfPresent([IndexSkill].self, forKey: .skills) ?? []
        repos = try c.decodeIfPresent([IndexRepo].self, forKey: .repos) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, generator, categories, featured, details, marketplaces, plugins, skills, repos
    }

    /// Version 1 catalogs carry file lists and findings in each item.
    public var hasInlineDetails: Bool { schemaVersion < 2 }
}

public struct DetailsLocation: Decodable, Sendable, Hashable {
    public let buckets: Int
    /// A URL with `{bucket}` to replace, or nil for a catalog built outside a release.
    public let url: String?
}

public struct FeaturedPick: Decodable, Sendable, Hashable {
    public let id: String
    public let kind: ItemKind
    public let note: String?
}

public enum ItemKind: String, Decodable, Sendable, Hashable, CaseIterable {
    case skill, plugin
}

/// A string enum that decodes values it doesn't know as `unknown` instead of failing.
public protocol LenientEnum: RawRepresentable, Decodable where RawValue == String {
    static var unknown: Self { get }
}

public extension LenientEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}

public enum RiskLevel: String, LenientEnum, Sendable, Hashable, Comparable, CaseIterable {
    case low, medium, high, unknown

    /// Unknown sorts as the most severe: a level the app can't read is never shown as safe.
    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .unknown: 3
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rank < rhs.rank }
}

public enum Publisher: String, LenientEnum, Sendable, Hashable {
    case anthropic
    case thirdParty = "third_party"
    case unknown
}

public enum FileKind: String, LenientEnum, Sendable, Hashable {
    case doc, script, data, asset, archive, binary, unknown
}

public enum FindingContext: String, LenientEnum, Sendable, Hashable {
    case code, comment, documentation, file, unknown
}

public struct IndexFile: Decodable, Sendable, Hashable {
    public let path: String
    public let size: Int64
    /// Git blob SHA-1 of the contents. Absent in indexes built before SkillsFlow 0.2.
    public let sha: String?
    public let kind: FileKind
    public let executable: Bool

    public init(path: String, size: Int64, sha: String?, kind: FileKind, executable: Bool) {
        self.path = path
        self.size = size
        self.sha = sha
        self.kind = kind
        self.executable = executable
    }
}

public struct Finding: Decodable, Sendable, Hashable {
    public let rule: String
    public let severity: RiskLevel
    public let summary: String
    public let file: String
    public let line: Int?
    public let excerpt: String?
    public let context: FindingContext
}

public enum AutomaticKind: String, LenientEnum, Sendable, Hashable, CaseIterable {
    case hooks
    case mcpServers = "mcp_servers"
    case lspServers = "lsp_servers"
    case monitors
    case mods
    case bin
    case unknown
}

/// The findings of one rule, summarized.
public struct RuleTally: Decodable, Sendable, Hashable {
    public let count: Int
    public let severity: RiskLevel
    public let summary: String
}

public struct SecurityReport: Decodable, Sendable, Hashable {
    public let risk: RiskLevel
    public let scripts: Int
    public let binaries: Int
    /// Inline in version 1 catalogs; in a detail shard from version 2.
    public let findings: [Finding]
    /// Rule ID to a summary of its findings, always available.
    public let rules: [String: RuleTally]
    /// Plugins only.
    public let runsCodeAutomatically: [AutomaticKind]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        risk = try c.decode(RiskLevel.self, forKey: .risk)
        scripts = try c.decodeIfPresent(Int.self, forKey: .scripts) ?? 0
        binaries = try c.decodeIfPresent(Int.self, forKey: .binaries) ?? 0
        findings = try c.decodeIfPresent([Finding].self, forKey: .findings) ?? []
        rules = try c.decodeIfPresent([String: RuleTally].self, forKey: .rules) ?? Self.tally(findings)
        runsCodeAutomatically = try c.decodeIfPresent([AutomaticKind].self, forKey: .runsCodeAutomatically) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case risk, scripts, binaries, findings, rules, runsCodeAutomatically
    }

    static func tally(_ findings: [Finding]) -> [String: RuleTally] {
        Dictionary(grouping: findings, by: \.rule).mapValues { group in
            RuleTally(count: group.count, severity: group.map(\.severity).max() ?? .low, summary: group[0].summary)
        }
    }
}

public struct StarsGained: Decodable, Sendable, Hashable {
    public let count: Int
    public let days: Int
}

public struct CopyInstall: Decodable, Sendable, Hashable {
    public let repo: String
    public let path: String
    public let commit: String
    /// `~/.claude/skills/<folder>`.
    public let target: String

    public var folderName: String {
        (target as NSString).lastPathComponent
    }
}

public struct SkillInstall: Decodable, Sendable, Hashable {
    public let plugins: [String]
    public let copy: CopyInstall
}

public struct IndexSkill: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let license: String?
    public let repo: String
    public let path: String
    public let commit: String
    public let url: String
    public let frontmatter: [String: JSONValue]
    public let lines: Int
    /// Inline in version 1 catalogs; in a detail shard from version 2.
    public let files: [IndexFile]
    public let fileCount: Int
    public let filesSize: Int64
    /// See `FilesDigest`. Nil only for a version 1 catalog without file hashes.
    public let filesDigest: String?
    /// Git blob SHA-1 of `SKILL.md`.
    public let skillFileSHA: String?
    /// The folder has `.claude-plugin/plugin.json`, so Claude Code loads a copy of it as a plugin.
    public let folderIsPlugin: Bool
    public let security: SecurityReport
    public let trust: String?
    public let publisher: Publisher?
    public let listedByAnthropic: Bool?
    public let stars: Int?
    public let starsGained: StarsGained?
    public let repoPushedAt: String?
    public let plugins: [String]
    public let category: String
    public let firstSeen: String
    public let added: String?
    public let install: SkillInstall

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        license = try c.decodeIfPresent(String.self, forKey: .license)
        repo = try c.decode(String.self, forKey: .repo)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        commit = try c.decode(String.self, forKey: .commit)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? "https://github.com/\(repo)"
        frontmatter = try c.decodeIfPresent([String: JSONValue].self, forKey: .frontmatter) ?? [:]
        lines = try c.decodeIfPresent(Int.self, forKey: .lines) ?? 0
        let files = try c.decodeIfPresent([IndexFile].self, forKey: .files) ?? []
        self.files = files
        fileCount = try c.decodeIfPresent(Int.self, forKey: .fileCount) ?? files.count
        filesSize = try c.decodeIfPresent(Int64.self, forKey: .filesSize) ?? files.reduce(0) { $0 + $1.size }
        filesDigest = try c.decodeIfPresent(String.self, forKey: .filesDigest) ?? FilesDigest.of(files)
        skillFileSHA = try c.decodeIfPresent(String.self, forKey: .skillMdSha) ?? files.first { $0.path == "SKILL.md" }?.sha
        folderIsPlugin = try c.decodeIfPresent(Bool.self, forKey: .folderIsPlugin)
            ?? files.contains { $0.path == ".claude-plugin/plugin.json" }
        security = try c.decode(SecurityReport.self, forKey: .security)
        trust = try c.decodeIfPresent(String.self, forKey: .trust)
        publisher = try c.decodeIfPresent(Publisher.self, forKey: .publisher)
        listedByAnthropic = try c.decodeIfPresent(Bool.self, forKey: .listedByAnthropic)
        stars = try c.decodeIfPresent(Int.self, forKey: .stars)
        starsGained = try c.decodeIfPresent(StarsGained.self, forKey: .starsGained)
        repoPushedAt = try c.decodeIfPresent(String.self, forKey: .repoPushedAt)
        plugins = try c.decodeIfPresent([String].self, forKey: .plugins) ?? []
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "Other"
        firstSeen = try c.decodeIfPresent(String.self, forKey: .firstSeen) ?? ""
        added = try c.decodeIfPresent(String.self, forKey: .added)
        install = try c.decode(SkillInstall.self, forKey: .install)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, license, repo, path, commit, url, frontmatter, lines, files, fileCount, filesSize
        case filesDigest, skillMdSha, folderIsPlugin, security, trust
        case publisher, listedByAnthropic, stars, starsGained, repoPushedAt, plugins, category, firstSeen, added, install
    }
}

public struct PluginSource: Decodable, Sendable, Hashable {
    public let type: String
    public let repo: String?
    public let path: String?
    public let ref: String?
    public let sha: String?
}

public struct PluginComponents: Decodable, Sendable, Hashable {
    public let skills: Int
    public let commands: Int
    public let agents: Int
    public let hooks: Bool
    public let mcpServers: Bool
    public let lspServers: Bool
    public let monitors: Bool
    public let mods: Bool
    public let bin: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skills = try c.decodeIfPresent(Int.self, forKey: .skills) ?? 0
        commands = try c.decodeIfPresent(Int.self, forKey: .commands) ?? 0
        agents = try c.decodeIfPresent(Int.self, forKey: .agents) ?? 0
        hooks = try c.decodeIfPresent(Bool.self, forKey: .hooks) ?? false
        mcpServers = try c.decodeIfPresent(Bool.self, forKey: .mcpServers) ?? false
        lspServers = try c.decodeIfPresent(Bool.self, forKey: .lspServers) ?? false
        monitors = try c.decodeIfPresent(Bool.self, forKey: .monitors) ?? false
        mods = try c.decodeIfPresent(Bool.self, forKey: .mods) ?? false
        bin = try c.decodeIfPresent(Bool.self, forKey: .bin) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case skills, commands, agents, hooks, mcpServers, lspServers, monitors, mods, bin
    }
}

/// One thing a plugin starts on its own: a hook, server, monitor or mod.
public struct AutomaticEntry: Decodable, Sendable, Hashable {
    public let name: String?
    public let event: String?
    public let matcher: String?
    public let type: String?
    /// The command line, URL or prompt; for mods, the module path.
    public let command: String
    public let env: [String]
    /// Where it's declared, relative to the plugin folder.
    public let file: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        event = try c.decodeIfPresent(String.self, forKey: .event)
        matcher = try c.decodeIfPresent(String.self, forKey: .matcher)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        command = try c.decodeIfPresent(String.self, forKey: .command)
            ?? c.decodeIfPresent(String.self, forKey: .module) ?? ""
        env = try c.decodeIfPresent([String].self, forKey: .env) ?? []
        file = try c.decodeIfPresent(String.self, forKey: .file)
    }

    private enum CodingKeys: String, CodingKey {
        case name, event, matcher, type, command, module, env, file
    }
}

public struct AutomaticComponents: Decodable, Sendable, Hashable {
    public let hooks: [AutomaticEntry]
    public let mcpServers: [AutomaticEntry]
    public let lspServers: [AutomaticEntry]
    public let monitors: [AutomaticEntry]
    public let mods: [AutomaticEntry]
    public let bin: [String]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hooks = try c.decodeIfPresent([AutomaticEntry].self, forKey: .hooks) ?? []
        mcpServers = try c.decodeIfPresent([AutomaticEntry].self, forKey: .mcpServers) ?? []
        lspServers = try c.decodeIfPresent([AutomaticEntry].self, forKey: .lspServers) ?? []
        monitors = try c.decodeIfPresent([AutomaticEntry].self, forKey: .monitors) ?? []
        mods = try c.decodeIfPresent([AutomaticEntry].self, forKey: .mods) ?? []
        bin = try c.decodeIfPresent([String].self, forKey: .bin) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case hooks, mcpServers, lspServers, monitors, mods, bin
    }

    public var isEmpty: Bool {
        hooks.isEmpty && mcpServers.isEmpty && lspServers.isEmpty && monitors.isEmpty && mods.isEmpty && bin.isEmpty
    }
}

public struct IndexPlugin: Decodable, Sendable, Identifiable {
    /// `name@marketplace`, the ID `claude plugin install` takes.
    public let id: String
    public let name: String
    public let marketplace: String
    public let displayName: String?
    public let description: String?
    public let version: String?
    public let author: String?
    public let homepage: String?
    public let license: String?
    public let category: String
    public let tags: [String]
    public let source: PluginSource
    public let installCommand: String
    public let trust: String?
    public let publisher: Publisher?
    public let listedByAnthropic: Bool?
    public let indexed: Bool
    public let repo: String?
    public let path: String?
    public let commit: String?
    public let manifestName: String?
    public let skills: [String]
    /// The plugin's own files. Inline in version 1 catalogs; in a detail shard from version 2.
    public let files: [IndexFile]
    public let fileCount: Int
    public let filesSize: Int64
    public let filesDigest: String?
    public let components: PluginComponents?
    public let automatic: AutomaticComponents?
    public let security: SecurityReport?
    public let stars: Int?
    public let starsGained: StarsGained?
    public let firstSeen: String
    public let added: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        marketplace = try c.decode(String.self, forKey: .marketplace)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        homepage = try c.decodeIfPresent(String.self, forKey: .homepage)
        license = try c.decodeIfPresent(String.self, forKey: .license)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "Other"
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        source = try c.decode(PluginSource.self, forKey: .source)
        installCommand = try c.decodeIfPresent(String.self, forKey: .installCommand) ?? "claude plugin install \(id)"
        trust = try c.decodeIfPresent(String.self, forKey: .trust)
        publisher = try c.decodeIfPresent(Publisher.self, forKey: .publisher)
        listedByAnthropic = try c.decodeIfPresent(Bool.self, forKey: .listedByAnthropic)
        indexed = try c.decodeIfPresent(Bool.self, forKey: .indexed) ?? false
        repo = try c.decodeIfPresent(String.self, forKey: .repo)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        commit = try c.decodeIfPresent(String.self, forKey: .commit)
        manifestName = try c.decodeIfPresent(String.self, forKey: .manifestName)
        skills = try c.decodeIfPresent([String].self, forKey: .skills) ?? []
        let files = try c.decodeIfPresent([IndexFile].self, forKey: .files) ?? []
        self.files = files
        fileCount = try c.decodeIfPresent(Int.self, forKey: .fileCount) ?? files.count
        filesSize = try c.decodeIfPresent(Int64.self, forKey: .filesSize) ?? files.reduce(0) { $0 + $1.size }
        filesDigest = try c.decodeIfPresent(String.self, forKey: .filesDigest) ?? FilesDigest.of(files)
        components = try c.decodeIfPresent(PluginComponents.self, forKey: .components)
        automatic = try c.decodeIfPresent(AutomaticComponents.self, forKey: .automatic)
        security = try c.decodeIfPresent(SecurityReport.self, forKey: .security)
        stars = try c.decodeIfPresent(Int.self, forKey: .stars)
        starsGained = try c.decodeIfPresent(StarsGained.self, forKey: .starsGained)
        firstSeen = try c.decodeIfPresent(String.self, forKey: .firstSeen) ?? ""
        added = try c.decodeIfPresent(String.self, forKey: .added)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, marketplace, displayName, description, version, author, homepage, license, category, tags
        case source, installCommand, trust, publisher, listedByAnthropic, indexed, repo, path, commit, manifestName
        case skills, files, fileCount, filesSize, filesDigest, components, automatic, security, stars, starsGained
        case firstSeen, added
    }
}

public struct IndexMarketplace: Decodable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let repo: String
    public let commit: String?
    public let description: String?
    public let owner: String?
    public let trust: String?
    public let publisher: Publisher?
    public let addCommand: String
    public let plugins: [String]
}

public struct IndexRepo: Decodable, Sendable {
    public let slug: String
    public let commit: String?
    public let description: String?
    public let stars: Int?
    public let pushedAt: String?
    public let license: String?
    public let starsGained: StarsGained?
}
