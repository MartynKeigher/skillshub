import Foundation

/// How a skill folder on disk relates to the catalog.
public enum LocalSkillStatus: Sendable, Hashable {
    /// Installed or adopted by SkillsHub: it has a receipt naming this catalog skill.
    case linked(skillID: String, updateAvailable: Bool)
    /// Has a receipt, but the skill is no longer in the catalog.
    case linkedNotInCatalog(skillID: String)
    /// No receipt, but its `SKILL.md` is identical to a catalog skill's. Can be adopted.
    case matches(skillID: String)
    /// No receipt; a catalog skill has the same folder name but different contents.
    case resembles(skillIDs: [String])
    /// Not from the catalog, as far as SkillsHub can tell.
    case unknown

    public var skillID: String? {
        switch self {
        case let .linked(id, _), let .linkedNotInCatalog(id), let .matches(id): id
        case .resembles, .unknown: nil
        }
    }
}

public enum InstallState: Sendable, Hashable {
    case notInstalled
    case installed
    case updateAvailable
}

/// Everything installed that relates to one catalog item.
public struct ItemLocalState: Sendable, Hashable {
    public let state: InstallState
    /// Skill folders holding this skill.
    public let folders: [LocalSkillFolder]
    /// Installations of this plugin, or of the plugins that bring this skill.
    public let pluginInstalls: [InstalledPlugin]
    /// For a skill: installed plugins that load it.
    public let viaPlugins: [String]

    public static let empty = ItemLocalState(state: .notInstalled, folders: [], pluginInstalls: [], viaPlugins: [])

    /// Installed only at project or local scope, which v1 shows but doesn't manage.
    public var isProjectScopedOnly: Bool {
        !pluginInstalls.isEmpty && folders.isEmpty
            && pluginInstalls.allSatisfy { $0.scope == .project || $0.scope == .local }
    }
}

/// What's installed, related to a catalog. Built from a scan and the plugin list; holds no state
/// of its own beyond them.
public struct LocalSnapshot: Sendable {
    public let folders: [LocalSkillFolder]
    public let plugins: [InstalledPlugin]
    public let folderStatus: [String: LocalSkillStatus]
    private let foldersBySkill: [String: [LocalSkillFolder]]
    private let installsByPlugin: [String: [InstalledPlugin]]
    private let catalog: Catalog

    public init(folders: [LocalSkillFolder], plugins: [InstalledPlugin], catalog: Catalog) {
        self.folders = folders
        self.plugins = plugins
        self.catalog = catalog
        let skillsByFolderName = Dictionary(grouping: catalog.index.skills, by: { $0.install.copy.folderName.lowercased() })
        let skillsByName = Dictionary(grouping: catalog.index.skills, by: { $0.name.lowercased() })
        var status: [String: LocalSkillStatus] = [:]
        var bySkill: [String: [LocalSkillFolder]] = [:]
        for folder in folders {
            let result = Self.status(of: folder, catalog: catalog, byFolderName: skillsByFolderName, byName: skillsByName)
            status[folder.id] = result
            switch result {
            case let .linked(id, _), let .matches(id):
                bySkill[id, default: []].append(folder)
            default:
                break
            }
        }
        folderStatus = status
        foldersBySkill = bySkill
        installsByPlugin = Dictionary(grouping: plugins, by: \.pluginID)
    }

    public func state(of item: CatalogItem) -> ItemLocalState {
        switch item.kind {
        case .plugin:
            let installs = installsByPlugin[item.id] ?? []
            guard !installs.isEmpty, let plugin = catalog.pluginsByID[item.id] else { return .empty }
            let update = installs.contains { Self.pluginUpdateAvailable(installed: $0, indexed: plugin) }
            return ItemLocalState(state: update ? .updateAvailable : .installed, folders: [], pluginInstalls: installs, viaPlugins: [])
        case .skill:
            let folders = foldersBySkill[item.id] ?? []
            let viaPlugins = (catalog.skillsByID[item.id]?.plugins ?? []).filter { installsByPlugin[$0] != nil }
            let installs = viaPlugins.flatMap { installsByPlugin[$0] ?? [] }
            guard !folders.isEmpty || !viaPlugins.isEmpty else { return .empty }
            let folderUpdate = folders.contains {
                if case .linked(_, true) = folderStatus[$0.id] { return true }
                return false
            }
            let pluginUpdate = viaPlugins.contains { id in
                guard let plugin = catalog.pluginsByID[id] else { return false }
                return (installsByPlugin[id] ?? []).contains { Self.pluginUpdateAvailable(installed: $0, indexed: plugin) }
            }
            return ItemLocalState(state: folderUpdate || pluginUpdate ? .updateAvailable : .installed,
                                  folders: folders, pluginInstalls: installs, viaPlugins: viaPlugins)
        }
    }

    /// Folders that could be linked to their catalog source.
    public var adoptable: [(folder: LocalSkillFolder, skillID: String)] {
        folders.compactMap { folder in
            if case let .matches(id) = folderStatus[folder.id] { return (folder: folder, skillID: id) }
            return nil
        }
    }

    // MARK: Rules

    static func status(of folder: LocalSkillFolder, catalog: Catalog, byFolderName: [String: [IndexSkill]],
                       byName: [String: [IndexSkill]]) -> LocalSkillStatus {
        if let receipt = folder.receipt {
            guard let skill = catalog.skillsByID[receipt.id] else { return .linkedNotInCatalog(skillID: receipt.id) }
            return .linked(skillID: skill.id, updateAvailable: skillUpdateAvailable(receipt: receipt, indexed: skill))
        }
        let key = folder.name.lowercased()
        var candidates = byFolderName[key] ?? []
        if let declared = folder.declaredName?.lowercased() {
            candidates += (byName[declared] ?? []).filter { c in !candidates.contains { $0.id == c.id } }
        }
        guard !candidates.isEmpty else { return .unknown }
        if let hash = folder.skillFileHash {
            let exact = candidates.filter { $0.skillFileSHA == hash }
            // Several identical copies across repos: prefer Anthropic's, then the most starred.
            if let best = exact.max(by: { rank($0) < rank($1) }) {
                return .matches(skillID: best.id)
            }
        }
        return .resembles(skillIDs: candidates.map(\.id).sorted())
    }

    private static func rank(_ skill: IndexSkill) -> (Int, Int) {
        (TrustLabel.isAnthropicRepo(skill.repo) ? 1 : 0, skill.stars ?? 0)
    }

    /// The catalog's files differ from what the receipt says was installed. Compares the files
    /// digest when the catalog has one; otherwise any new commit counts, which can over-report.
    static func skillUpdateAvailable(receipt: SkillReceipt, indexed skill: IndexSkill) -> Bool {
        if let digest = skill.filesDigest {
            return digest != FilesDigest.of(receipt.files)
        }
        return receipt.commit != skill.commit
    }

    /// Mirrors how `claude plugin update` decides: a pinned version wins; without one, the
    /// source's commit decides. Never reports an update the CLI wouldn't install.
    static func pluginUpdateAvailable(installed: InstalledPlugin, indexed plugin: IndexPlugin) -> Bool {
        if let version = plugin.version, !version.isEmpty {
            return installed.version != version
        }
        // Inside its marketplace's repository, the CLI versions a plugin by the last commit that
        // touched its folder, which the index doesn't record. The repository's commit moves with
        // every other change, so it can't tell.
        guard plugin.source.type != "relative", let commit = plugin.commit else { return false }
        if let installedCommit = installed.gitCommitSha {
            return installedCommit != commit
        }
        return !installed.version.hasPrefix(String(commit.prefix(12)))
    }
}
