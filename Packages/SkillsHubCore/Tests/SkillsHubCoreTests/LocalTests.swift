import XCTest
@testable import SkillsHubCore

final class LocalTests: XCTestCase {
    var root: URL!
    var catalog: Catalog!

    override func setUpWithError() throws {
        root = try makeTemporaryDirectory()
        catalog = try Fixtures.catalog("catalog-v2")
    }

    private func scan(_ roots: [SkillsRoot]? = nil) async -> [LocalSkillFolder] {
        await FileSystemSkillsScanner().scan(roots ?? [SkillsRoot(location: .personal, url: root)])
    }

    // MARK: Scanner

    func testScannerReadsFoldersTheWayClaudeCodeFindsThem() async throws {
        try write("---\nname: \"fancy\"\ndescription: d\n---\nbody\n", to: root.appendingPathComponent("tidy/SKILL.md"))
        try write("{}", to: root.appendingPathComponent("plug/.claude-plugin/plugin.json"))
        try write("x", to: root.appendingPathComponent("plug/SKILL.md"))
        try write("x", to: root.appendingPathComponent("synced/a/SKILL.md"))      // claude.ai's, not the user's
        try write("x", to: root.appendingPathComponent(".hidden/SKILL.md"))
        try write("x", to: root.appendingPathComponent("loose-file.md"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let target = try makeTemporaryDirectory().appendingPathComponent("elsewhere")
        try write("x", to: target.appendingPathComponent("SKILL.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: target)

        let folders = await scan()
        XCTAssertEqual(folders.map(\.name), ["empty", "linked", "plug", "tidy"])
        let byName = Dictionary(uniqueKeysWithValues: folders.map { ($0.name, $0) })
        XCTAssertEqual(byName["tidy"]?.declaredName, "fancy")
        XCTAssertEqual(byName["tidy"]?.skillFileHash, GitBlobHash.of(Data("---\nname: \"fancy\"\ndescription: d\n---\nbody\n".utf8)))
        XCTAssertTrue(byName["plug"]?.isPlugin ?? false)
        XCTAssertTrue(byName["linked"]?.isLink ?? false)
        XCTAssertTrue(byName["linked"]?.hasSkillFile ?? false)
        XCTAssertFalse(byName["empty"]?.hasSkillFile ?? true)
    }

    func testMissingRootsAreSkipped() async {
        let folders = await scan([SkillsRoot(location: .project(root), url: root.appendingPathComponent("nope"))])
        XCTAssertTrue(folders.isEmpty)
    }

    func testReceiptRoundTrips() throws {
        let receipt = SkillReceipt(id: "a/b:c", repo: "a/b", path: "c", commit: "c1",
                                   installedAt: Date(timeIntervalSince1970: 1_800_000_000), files: ["SKILL.md": "aa"])
        try receipt.write(to: root)
        XCTAssertEqual(SkillReceipt.read(from: root), receipt)
    }

    // MARK: Matching

    private func folder(_ name: String, skillMD: String? = nil, receipt: SkillReceipt? = nil, declared: String? = nil) -> LocalSkillFolder {
        LocalSkillFolder(location: .personal, url: root.appendingPathComponent(name), name: name, hasSkillFile: true,
                         isLink: false, isPlugin: false, receipt: receipt, skillFileHash: skillMD, declaredName: declared)
    }

    private func receipt(for id: String, files: [String: String]) -> SkillReceipt {
        SkillReceipt(id: id, repo: "r", path: "p", commit: "c", installedAt: .now, files: files)
    }

    func testLinkedFolderWithMatchingFilesIsUpToDate() throws {
        let files = ["SKILL.md": String(repeating: "e", count: 40), "scripts/go.py": String(repeating: "f", count: 40)]
        let snap = LocalSnapshot(folders: [folder("setup", receipt: receipt(for: "lonely/skills:setup", files: files))],
                                 plugins: [], catalog: catalog)
        XCTAssertEqual(snap.folderStatus.values.first, .linked(skillID: "lonely/skills:setup", updateAvailable: false))
        XCTAssertEqual(snap.state(of: try XCTUnwrap(catalog.item(id: "lonely/skills:setup"))).state, .installed)
    }

    func testLinkedFolderWithDifferentFilesHasAnUpdate() throws {
        let snap = LocalSnapshot(folders: [folder("setup", receipt: receipt(for: "lonely/skills:setup", files: ["SKILL.md": "old"]))],
                                 plugins: [], catalog: catalog)
        XCTAssertEqual(snap.folderStatus.values.first, .linked(skillID: "lonely/skills:setup", updateAvailable: true))
        XCTAssertEqual(snap.state(of: try XCTUnwrap(catalog.item(id: "lonely/skills:setup"))).state, .updateAvailable)
    }

    func testReceiptForASkillNoLongerInTheCatalog() {
        let snap = LocalSnapshot(folders: [folder("gone", receipt: receipt(for: "x/y:gone", files: [:]))], plugins: [], catalog: catalog)
        XCTAssertEqual(snap.folderStatus.values.first, .linkedNotInCatalog(skillID: "x/y:gone"))
    }

    func testIdenticalSkillFileMatchesTheRightSourceAmongNamesakes() throws {
        // Two catalog skills install to ~/.claude/skills/setup; the SKILL.md decides which this is.
        let snap = LocalSnapshot(folders: [folder("setup", skillMD: String(repeating: "1", count: 40))], plugins: [], catalog: catalog)
        XCTAssertEqual(snap.folderStatus.values.first, .matches(skillID: "other/skills:setup"))
        XCTAssertEqual(snap.adoptable.map(\.skillID), ["other/skills:setup"])
        XCTAssertEqual(snap.state(of: try XCTUnwrap(catalog.item(id: "other/skills:setup"))).state, .installed)
        XCTAssertEqual(snap.state(of: try XCTUnwrap(catalog.item(id: "lonely/skills:setup"))).state, .notInstalled)
    }

    func testSameNameDifferentContentOnlyResembles() {
        let snap = LocalSnapshot(folders: [folder("setup", skillMD: "edited")], plugins: [], catalog: catalog)
        XCTAssertEqual(snap.folderStatus.values.first, .resembles(skillIDs: ["lonely/skills:setup", "other/skills:setup"]))
        XCTAssertTrue(snap.adoptable.isEmpty)
    }

    func testFrontmatterNameAlsoFindsCandidates() {
        let snap = LocalSnapshot(folders: [folder("my-fmt", skillMD: String(repeating: "a", count: 40), declared: "fmt")],
                                 plugins: [], catalog: catalog)
        XCTAssertEqual(snap.folderStatus.values.first, .matches(skillID: "anthropics/mp:plugins/official-tool/skills/fmt"))
    }

    func testUnrelatedFolderIsUnknown() {
        let snap = LocalSnapshot(folders: [folder("mine", skillMD: "zz")], plugins: [], catalog: catalog)
        XCTAssertEqual(snap.folderStatus.values.first, .unknown)
    }

    // MARK: Plugins

    private func installed(_ id: String, version: String, sha: String? = nil, scope: PluginScope = .user) -> InstalledPlugin {
        InstalledPlugin(pluginID: id, version: version, scope: scope, enabled: true, gitCommitSha: sha)
    }

    func testSkillInstalledThroughItsPlugin() throws {
        let snap = LocalSnapshot(folders: [], plugins: [installed("official-tool@anthropic-mp", version: "1.0.0")], catalog: catalog)
        let state = snap.state(of: try XCTUnwrap(catalog.item(id: "anthropics/mp:plugins/official-tool/skills/fmt")))
        XCTAssertEqual(state.state, .installed)
        XCTAssertEqual(state.viaPlugins, ["official-tool@anthropic-mp"])
    }

    func testPinnedVersionDecidesPluginUpdates() throws {
        let plugin = try XCTUnwrap(catalog.pluginsByID["official-tool@anthropic-mp"])
        XCTAssertFalse(LocalSnapshot.pluginUpdateAvailable(installed: installed(plugin.id, version: "1.0.0", sha: "other"), indexed: plugin))
        XCTAssertTrue(LocalSnapshot.pluginUpdateAvailable(installed: installed(plugin.id, version: "0.9.0"), indexed: plugin))
    }

    func testUnpinnedPluginsCompareCommits() throws {
        let partner = try XCTUnwrap(catalog.pluginsByID["partner@anthropic-mp"]) // github source, no version
        XCTAssertFalse(LocalSnapshot.pluginUpdateAvailable(installed: installed(partner.id, version: "x", sha: "c2"), indexed: partner))
        XCTAssertTrue(LocalSnapshot.pluginUpdateAvailable(installed: installed(partner.id, version: "x", sha: "c0"), indexed: partner))
    }

    func testUnpinnedPluginsInsideTheirMarketplaceNeverClaimAnUpdate() throws {
        let rel = try XCTUnwrap(catalog.pluginsByID["rel@anthropic-mp"])
        XCTAssertFalse(LocalSnapshot.pluginUpdateAvailable(installed: installed(rel.id, version: "abc", sha: "different"), indexed: rel))
    }

    func testProjectScopedInstallsAreFlagged() throws {
        let snap = LocalSnapshot(folders: [], plugins: [installed("indie-tool@indie", version: "2.0", scope: .project)], catalog: catalog)
        XCTAssertTrue(snap.state(of: try XCTUnwrap(catalog.item(id: "indie-tool@indie"))).isProjectScopedOnly)
    }
}
