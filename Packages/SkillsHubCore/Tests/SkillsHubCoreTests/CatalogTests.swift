import XCTest
@testable import SkillsHubCore

final class CatalogTests: XCTestCase {
    var catalog: Catalog!

    override func setUpWithError() throws {
        catalog = try Fixtures.catalog()
    }

    private func item(_ id: String) throws -> CatalogItem {
        try XCTUnwrap(catalog.item(id: id), id)
    }

    // MARK: Trust

    func testTrustLabelsSeparateMakerFromListing() throws {
        XCTAssertEqual(try item("official-tool@anthropic-mp").trust, .anthropic)
        XCTAssertEqual(try item("partner@anthropic-mp").trust, .anthropicMarketplace)
        XCTAssertEqual(try item("indie-tool@indie").trust, .community)
        XCTAssertEqual(try item("lonely/skills:setup").trust, .community)
        XCTAssertEqual(TrustLabel.anthropicMarketplace.title, "Anthropic's marketplace")
    }

    func testTrustFallsBackToTheRepositoryOwnerForOlderIndexes() throws {
        XCTAssertEqual(try item("anthropics/legacy:pdf").trust, .anthropic)
        let live = try Fixtures.catalog("live-sample")
        // In the old index this third-party plugin read "official"; the label must not.
        let crunch = try XCTUnwrap(live.item(id: "42crunch-api-security-testing@claude-plugins-official"))
        XCTAssertEqual(crunch.trust, .anthropicMarketplace)
        XCTAssertEqual(live.item(id: "commit-commands@claude-plugins-official")?.trust, .anthropic)
    }

    // MARK: Security

    func testPluginRiskIncludesItsSkills() throws {
        let partner = try item("partner@anthropic-mp")
        XCTAssertEqual(partner.risk, .high) // its own scan is medium; a skill it loads is high
        XCTAssertEqual(partner.security.runsAutomatically, [.hooks, .mcpServers])
        XCTAssertEqual(partner.security.scripts, 1)
        XCTAssertEqual(partner.security.rules.map(\.rule), ["pipe-to-shell", "network-code", "secret-names"])
        XCTAssertEqual(partner.security.rules.first?.severity, .high)
        XCTAssertEqual(partner.security.findingCount, 3)
    }

    func testSchemaTwoGivesTheSameSummaries() throws {
        let v2 = try Fixtures.catalog("catalog-v2")
        for item in catalog.items where item.id != "anthropics/legacy:pdf" {
            let other = try XCTUnwrap(v2.item(id: item.id))
            XCTAssertEqual(other.security, item.security, item.id)
            XCTAssertEqual(other.trust, item.trust, item.id)
        }
    }

    func testUnindexedPluginIsUnknownAndNotReviewable() throws {
        let plugin = try item("unreviewed@anthropic-mp")
        XCTAssertEqual(plugin.risk, .unknown)
        XCTAssertFalse(plugin.isReviewable)
        XCTAssertFalse(plugin.security.wasReviewed)
    }

    func testSkillFolderThatIsAlsoAPluginIsAtLeastMedium() throws {
        let skill = try item("weird/plugin-skill")
        XCTAssertTrue(skill.security.skillFolderIsPlugin)
        XCTAssertEqual(skill.risk, .medium)
    }

    func testRelativePathOfASkillInsideItsPlugin() throws {
        let plugin = try XCTUnwrap(catalog.pluginsByID["official-tool@anthropic-mp"])
        let skill = try XCTUnwrap(catalog.skillsByID["anthropics/mp:plugins/official-tool/skills/fmt"])
        XCTAssertEqual(plugin.relativePath(of: skill), "skills/fmt")
        let partner = try XCTUnwrap(catalog.pluginsByID["partner@anthropic-mp"])
        XCTAssertEqual(partner.relativePath(of: try XCTUnwrap(catalog.skillsByID["partner/tool"])), "")
    }

    // MARK: Relations

    func testPluginsContainingASkillPreferTheSafestSmallest() {
        XCTAssertEqual(catalog.plugins(containing: "someone/indie:skills/shared").map(\.id),
                       ["indie-tool@indie", "partner@anthropic-mp"])
        XCTAssertTrue(catalog.plugins(containing: "lonely/skills:setup").isEmpty)
    }

    // MARK: Search and sections

    func testSearchRanksNameMatchesFirstAndNeedsEveryTerm() {
        let results = catalog.items(matching: "setup")
        XCTAssertEqual(Set(results.prefix(2).map(\.id)), ["lonely/skills:setup", "other/skills:setup"])
        XCTAssertEqual(results.first?.id, "other/skills:setup") // same score, more stars
        XCTAssertTrue(catalog.items(matching: "setup nonsense").isEmpty)
        XCTAssertEqual(catalog.items(matching: "indie").first?.id, "indie-tool@indie")
    }

    func testFilters() {
        let plugins = catalog.items(matching: "", filter: .init(kind: .plugin))
        XCTAssertEqual(plugins.count, 5)
        let safe = catalog.items(matching: "", filter: .init(maximumRisk: .low))
        XCTAssertFalse(safe.contains { $0.risk > .low })
        XCTAssertFalse(safe.contains { $0.id == "unreviewed@anthropic-mp" }) // unknown is never "low"
        let devops = catalog.items(matching: "", filter: .init(category: "DevOps & Cloud"))
        XCTAssertEqual(devops.map(\.id), ["lonely/skills:setup"])
    }

    func testFeaturedSkipsMissingPicks() {
        XCTAssertEqual(catalog.featured.map(\.item.id), ["official-tool@anthropic-mp", "lonely/skills:setup"])
        XCTAssertEqual(catalog.featured.first?.note, "Format everything")
    }

    func testPopularCapsItemsPerRepository() {
        let popular = catalog.popular(limit: 10, perRepo: 1)
        let repos = popular.compactMap { $0.repo?.lowercased() }
        XCTAssertEqual(repos.count, Set(repos).count)
        XCTAssertEqual(popular.first?.repo, "anthropics/legacy") // 9000 stars
    }

    func testTrendingRanksByStarsGainedPerDay() {
        let trending = catalog.trending(limit: 10, perRepo: 1)
        XCTAssertEqual(trending.first?.repo, "anthropics/mp")
        XCTAssertTrue(trending.allSatisfy { ($0.starsGained?.count ?? 0) > 0 })
    }

    func testRecentlyAddedIgnoresTheFirstRunDate() throws {
        XCTAssertEqual(catalog.baselineDate, "2026-10-28")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-10T12:00:00Z"))
        let recent = catalog.recentlyAdded(within: 30, now: now)
        // Git dates count; so does first appearing after the first run. The first run's date doesn't.
        XCTAssertEqual(recent.map(\.id), [
            "indie-tool@indie", "someone/indie:skills/shared",
            "lonely/skills:setup",
            "anthropics/mp:plugins/official-tool/skills/fmt", "official-tool@anthropic-mp",
        ].sorted { lhs, rhs in
            let l = catalog.addedDate(of: catalog.item(id: lhs)!)!, r = catalog.addedDate(of: catalog.item(id: rhs)!)!
            return l != r ? l > r : catalog.item(id: lhs)!.name < catalog.item(id: rhs)!.name
        })
        XCTAssertFalse(recent.contains { $0.id == "partner@anthropic-mp" })
        XCTAssertEqual(catalog.recentlyAdded(within: 10, now: now).map(\.id).first, "indie-tool@indie")
    }

    func testCategoryCountsFollowTheIndexOrder() {
        XCTAssertEqual(catalog.categoryCounts.map(\.category), ["Development", "DevOps & Cloud", "Productivity"])
    }
}
