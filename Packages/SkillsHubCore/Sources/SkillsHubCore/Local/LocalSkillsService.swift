import Foundation
import Observation

/// Whether Claude Code is installed, and which version.
public enum ClaudeStatus: Sendable, Equatable {
    case unknown
    case notInstalled
    /// Found, but older than the version whose `plugin` commands SkillsHub relies on.
    case outdated(version: ClaudeVersion, executable: URL)
    /// Found, but `claude --version` failed.
    case broken(executable: URL, message: String)
    case ready(version: ClaudeVersion, executable: URL)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var executable: URL? {
        switch self {
        case let .outdated(_, url), let .broken(url, _), let .ready(_, url): url
        case .unknown, .notInstalled: nil
        }
    }
}

/// What's installed, read from where Claude Code keeps it: skill folders on disk and
/// `claude plugin list`. Stands in for CaskHub's `LocalHomebrewService`. Like CaskHub, it keeps
/// no state of its own: every refresh reads the real locations again.
@MainActor
@Observable
public final class LocalSkillsService {
    public private(set) var claude: ClaudeStatus = .unknown
    public private(set) var folders: [LocalSkillFolder] = []
    public private(set) var plugins: [InstalledPlugin] = []
    /// Why the plugin list is incomplete, if it is.
    public private(set) var pluginListIssue: String?
    public private(set) var isRefreshing = false
    public private(set) var paths: ClaudePaths
    /// Project folders whose `.claude/skills` are scanned too. Chosen by the user.
    public var projectFolders: [URL] {
        didSet { if projectFolders != oldValue { projectFoldersChanged?(projectFolders) } }
    }
    /// A `claude` path the user chose in Settings; tried before the usual locations.
    public var customClaudePath: String?

    @ObservationIgnored public var projectFoldersChanged: (([URL]) -> Void)?
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let scanner: any SkillsScanning
    @ObservationIgnored private let locator: ClaudeLocator
    @ObservationIgnored private let makeCLI: @Sendable (ClaudeLocator.Installation) -> any ClaudeCLIProtocol
    @ObservationIgnored private var installation: ClaudeLocator.Installation?
    @ObservationIgnored private var snapshotCache: (key: String, snapshot: LocalSnapshot)?
    /// Changes whenever a refresh has read new state.
    public private(set) var revision = 0

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                projectFolders: [URL] = [],
                customClaudePath: String? = nil,
                scanner: any SkillsScanning = FileSystemSkillsScanner(),
                locator: ClaudeLocator = ClaudeLocator(),
                makeCLI: @escaping @Sendable (ClaudeLocator.Installation) -> any ClaudeCLIProtocol = {
                    ClaudeCLI(executable: $0.executable, environment: $0.environment)
                }) {
        self.home = home
        self.projectFolders = projectFolders
        self.customClaudePath = customClaudePath
        self.scanner = scanner
        self.locator = locator
        self.makeCLI = makeCLI
        paths = ClaudePaths(home: home)
    }

    public var roots: [SkillsRoot] {
        [SkillsRoot(location: .personal, url: paths.personalSkills)]
            + projectFolders.map { SkillsRoot(location: .project($0), url: ClaudePaths.projectSkills(in: $0)) }
    }

    /// Reads everything again. `relocateClaude` looks for the `claude` binary again too, as
    /// after the user installs it or changes the path in Settings.
    public func refresh(relocateClaude: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if installation == nil || relocateClaude {
            installation = await locator.locate(customPath: customClaudePath)
        }
        paths = ClaudePaths(home: home, environment: installation?.environment ?? [:])
        let records = PluginRecordsReader(file: paths.installedPluginsFile)

        async let scanned = scanner.scan(roots)
        var listed: [InstalledPlugin]
        var issue: String?
        if let installation {
            let cli = makeCLI(installation)
            do {
                let version = try await cli.version()
                claude = version >= .minimumSupported
                    ? .ready(version: version, executable: installation.executable)
                    : .outdated(version: version, executable: installation.executable)
            } catch {
                claude = .broken(executable: installation.executable, message: error.localizedDescription)
            }
            if claude.isReady {
                do {
                    listed = try await cli.listPlugins()
                } catch {
                    listed = records.installedPlugins()
                    issue = "Couldn't run `claude plugin list`, so plugins are read from Claude Code's records: \(error.localizedDescription)"
                }
            } else {
                listed = records.installedPlugins()
                issue = "Plugins are read from Claude Code's records until Claude Code is updated."
            }
        } else {
            claude = .notInstalled
            listed = records.installedPlugins()
        }
        let commits = Dictionary(records.records().map { ("\($0.pluginID)|\($0.scope.rawValue)|\($0.projectPath ?? "")", $0.gitCommitSha) },
                                 uniquingKeysWith: { first, _ in first })
        plugins = listed.map { plugin in
            var plugin = plugin
            if plugin.gitCommitSha == nil { plugin.gitCommitSha = commits[plugin.id] ?? nil }
            return plugin
        }
        pluginListIssue = issue
        folders = await scanned
        revision += 1
    }

    /// Installed state related to a catalog, rebuilt only when either changes.
    public func snapshot(for catalog: Catalog) -> LocalSnapshot {
        let key = "\(catalog.index.generatedAt)|\(revision)"
        if let cached = snapshotCache, cached.key == key { return cached.snapshot }
        let snapshot = LocalSnapshot(folders: folders, plugins: plugins, catalog: catalog)
        snapshotCache = (key, snapshot)
        return snapshot
    }
}
