import XCTest
@testable import SkillsHubCore

@MainActor
final class LocalSkillsServiceTests: XCTestCase {
    nonisolated(unsafe) var home: URL!

    override func setUpWithError() throws {
        home = try makeTemporaryDirectory()
    }

    private func service(locates: Bool, cli: FakeCLI? = nil, projects: [URL] = []) -> LocalSkillsService {
        let runner = FakeRunner(outputs: [:]) // no login shell: the app's own environment is used
        let claudePath = home.appendingPathComponent(".local/bin/claude").path
        let locator = ClaudeLocator(home: home, shell: "/bin/false", runner: runner,
                                    isExecutable: { locates && $0 == claudePath })
        return LocalSkillsService(home: home, projectFolders: projects, locator: locator,
                                  makeCLI: { _ in cli ?? FakeCLI(installedVersion: ClaudeVersion(2, 1, 312), plugins: []) })
    }

    func testWithoutClaudeCodeSkillsAreStillFound() async throws {
        try write("x", to: home.appendingPathComponent(".claude/skills/mine/SKILL.md"))
        let project = home.appendingPathComponent("proj")
        try write("x", to: project.appendingPathComponent(".claude/skills/team/SKILL.md"))
        let local = service(locates: false, projects: [project])
        await local.refresh()
        XCTAssertEqual(local.claude, .notInstalled)
        XCTAssertEqual(local.folders.map(\.name), ["mine", "team"])
        XCTAssertEqual(local.folders.last?.location, .project(project))
    }

    func testReadyClaudeListsPluginsWithTheirCommit() async throws {
        try write(#"{"version":2,"plugins":{"a@m":[{"scope":"user","version":"1","gitCommitSha":"abc"}]}}"#,
                  to: home.appendingPathComponent(".claude/plugins/installed_plugins.json"))
        let cli = FakeCLI(installedVersion: ClaudeVersion(2, 1, 312),
                          plugins: [InstalledPlugin(pluginID: "a@m", version: "1", scope: .user, enabled: true)])
        let local = service(locates: true, cli: cli)
        await local.refresh()
        XCTAssertTrue(local.claude.isReady)
        XCTAssertEqual(local.plugins.first?.gitCommitSha, "abc")
        XCTAssertNil(local.pluginListIssue)
    }

    func testOutdatedClaudeFallsBackToTheRecords() async throws {
        try write(#"{"version":2,"plugins":{"a@m":[{"scope":"user","version":"1"}]}}"#,
                  to: home.appendingPathComponent(".claude/plugins/installed_plugins.json"))
        let local = service(locates: true, cli: FakeCLI(installedVersion: ClaudeVersion(2, 0, 1), plugins: []))
        await local.refresh()
        guard case let .outdated(version, _) = local.claude else { return XCTFail("\(local.claude)") }
        XCTAssertEqual(version, ClaudeVersion(2, 0, 1))
        XCTAssertEqual(local.plugins.map(\.pluginID), ["a@m"])
        XCTAssertNotNil(local.pluginListIssue)
    }

    func testFailingPluginListFallsBackToTheRecords() async throws {
        let local = service(locates: true, cli: FakeCLI(installedVersion: ClaudeVersion(2, 1, 312), plugins: [], listFails: true))
        await local.refresh()
        XCTAssertTrue(local.claude.isReady)
        XCTAssertNotNil(local.pluginListIssue)
    }

    func testSnapshotIsRebuiltOnlyWhenSomethingChanges() async throws {
        let catalog = try Fixtures.catalog("catalog-v2")
        let local = service(locates: false)
        await local.refresh()
        let first = local.snapshot(for: catalog)
        XCTAssertTrue(first.folders.isEmpty)
        try write("x", to: home.appendingPathComponent(".claude/skills/new/SKILL.md"))
        XCTAssertTrue(local.snapshot(for: catalog).folders.isEmpty, "unchanged until the next refresh")
        await local.refresh()
        XCTAssertEqual(local.snapshot(for: catalog).folders.map(\.name), ["new"])
    }
}

/// Serves a catalog download through the index client.
struct FakeIndexClient: IndexClientProtocol {
    let result: @Sendable (String?) throws -> IndexFetchResult

    func fetchLatest(etag: String?) async throws -> IndexFetchResult { try result(etag) }
}

@MainActor
final class IndexStoreTests: XCTestCase {
    private func catalogData(generatedAt: String) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.data("catalog-v2")) as? [String: Any])
        json["generated_at"] = generatedAt
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testOpensTheNewerOfBundledAndCached() async throws {
        let cache = IndexCache(directory: try makeTemporaryDirectory())
        let old = try catalogData(generatedAt: "2026-11-01T00:00:00Z")
        let new = try catalogData(generatedAt: "2026-11-09T00:00:00Z")
        try cache.save(new, metadata: .init(etag: "e1", generatedAt: "2026-11-09T00:00:00Z"))
        let store = IndexStore(bundled: BundledIndex(generatedAt: "2026-11-01T00:00:00Z", load: { old }), cache: cache,
                               client: FakeIndexClient { _ in .notModified })
        await store.loadLocal()
        XCTAssertEqual(store.source, .cached)
        XCTAssertEqual(store.generatedAt, "2026-11-09T00:00:00Z")

        let newerApp = IndexStore(bundled: BundledIndex(generatedAt: "2026-11-10T00:00:00Z", load: { old }), cache: cache,
                                  client: FakeIndexClient { _ in .notModified })
        await newerApp.loadLocal()
        XCTAssertEqual(newerApp.source, .bundled, "an app update ships a newer catalog than the cache")
    }

    func testRefreshSwitchesOnlyToANewerCatalogAndSendsTheETag() async throws {
        let cache = IndexCache(directory: try makeTemporaryDirectory())
        let bundled = try catalogData(generatedAt: "2026-11-05T00:00:00Z")
        let newer = try catalogData(generatedAt: "2026-11-09T00:00:00Z")
        let seen = LockedBox<[String?]>([])
        let store = IndexStore(bundled: BundledIndex(generatedAt: nil, load: { bundled }), cache: cache,
                               client: FakeIndexClient { etag in
                                   seen.mutate { $0.append(etag) }
                                   return .updated(data: newer, etag: "e2")
                               })
        await store.loadLocal()
        XCTAssertEqual(store.source, .bundled)
        await store.refresh()
        XCTAssertEqual(store.source, .downloaded)
        XCTAssertEqual(store.generatedAt, "2026-11-09T00:00:00Z")
        XCTAssertEqual(cache.metadata(), .init(etag: "e2", generatedAt: "2026-11-09T00:00:00Z"))
        await store.refresh()
        XCTAssertEqual(seen.value, [nil, "e2"])
    }

    func testRefreshNeverGoesBackToAnOlderCatalog() async throws {
        let bundled = try catalogData(generatedAt: "2026-11-09T00:00:00Z")
        let older = try catalogData(generatedAt: "2026-11-01T00:00:00Z")
        let store = IndexStore(bundled: BundledIndex(generatedAt: nil, load: { bundled }), cache: nil,
                               client: FakeIndexClient { _ in .updated(data: older, etag: nil) })
        await store.loadLocal()
        await store.refresh()
        XCTAssertEqual(store.generatedAt, "2026-11-09T00:00:00Z")
        XCTAssertEqual(store.source, .bundled)
    }

    func testRefreshErrorsAreReportedNotThrown() async throws {
        let bundled = try catalogData(generatedAt: "2026-11-09T00:00:00Z")
        let store = IndexStore(bundled: BundledIndex(generatedAt: nil, load: { bundled }), cache: nil,
                               client: FakeIndexClient { _ in throw IndexClient.HTTPError(statusCode: 503) })
        await store.loadLocal()
        await store.refresh()
        XCTAssertNotNil(store.catalog)
        XCTAssertEqual(store.lastRefreshError, "The catalog download failed (HTTP 503).")
    }

    func testIndexClientSendsIfNoneMatchAndHandles304() async throws {
        StubURLProtocol.reset()
        let url = URL(string: "https://example.com/index.json")!
        StubURLProtocol.responses[url.absoluteString] = .init(status: 304)
        let client = IndexClient(url: url, session: StubURLProtocol.session())
        guard case .notModified = try await client.fetchLatest(etag: "\"abc\"") else { return XCTFail("expected 304") }
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match"), "\"abc\"")
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private var stored: Value
    private let lock = NSLock()

    init(_ value: Value) { stored = value }

    var value: Value { lock.withLock { stored } }

    func mutate(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}
