import AppKit
import Foundation
import Observation
import SkillsHubCore

/// Owns the catalog, the local state and the clients, and keeps the user's few preferences:
/// which project folders to scan, and a custom `claude` path. Like CaskHub, nothing about what's
/// installed is stored here; it's read from disk and from `claude` on every refresh.
@MainActor
@Observable
final class AppModel {
    let index: IndexStore
    let local: LocalSkillsService
    @ObservationIgnored let content: ContentClient
    @ObservationIgnored let details: DetailsClient

    private static let projectFoldersKey = "projectFolders"
    private static let customClaudePathKey = "customClaudePath"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "SkillsHub")
        index = IndexStore(bundled: BundledCatalog.make(),
                           cache: IndexCache(directory: caches.appendingPathComponent("Catalog")),
                           client: GzipIndexClient())
        content = ContentClient(cacheDirectory: caches.appendingPathComponent("Files"))
        details = DetailsClient(cacheDirectory: caches.appendingPathComponent("Details"))
        let projects = (defaults.stringArray(forKey: Self.projectFoldersKey) ?? []).map { URL(fileURLWithPath: $0) }
        local = LocalSkillsService(projectFolders: projects,
                                   customClaudePath: defaults.string(forKey: Self.customClaudePathKey))
        local.projectFoldersChanged = { [defaults] folders in
            defaults.set(folders.map(\.path), forKey: Self.projectFoldersKey)
        }
    }

    /// Opens the local catalog, reads what's installed, then refreshes the catalog online.
    func start() async {
        guard !started else { return }
        started = true
        observeActivation()
        await index.loadLocal()
        await local.refresh()
        await refreshCatalog()
    }

    func refreshCatalog() async {
        await index.refresh()
        if let catalog = index.catalog?.index { details.removeCaches(except: catalog) }
    }

    /// Reads skills folders and plugins again. After the user installs Claude Code or changes
    /// its path, `relocateClaude` looks for the binary again too.
    func refreshLocal(relocateClaude: Bool = false) async {
        await local.refresh(relocateClaude: relocateClaude)
    }

    var customClaudePath: String {
        get { local.customClaudePath ?? "" }
        set {
            local.customClaudePath = newValue.isEmpty ? nil : newValue
            defaults.set(newValue.isEmpty ? nil : newValue, forKey: Self.customClaudePathKey)
        }
    }

    func addProjectFolder(_ url: URL) {
        guard !local.projectFolders.contains(url) else { return }
        local.projectFolders.append(url)
        Task { await refreshLocal() }
    }

    func removeProjectFolder(_ url: URL) {
        local.projectFolders.removeAll { $0 == url }
        Task { await refreshLocal() }
    }

    /// Coming back to the app is the moment something may have changed in a terminal.
    private func observeActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.refreshLocal(relocateClaude: !self.local.claude.isReady)
            }
        }
    }
}
