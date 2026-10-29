import XCTest
@testable import SkillsHubCore

final class IndexDecodingTests: XCTestCase {
    func testDecodesTheLiveFormatWithoutNewerFields() throws {
        let index = try IndexDecoding.decode(Fixtures.data("live-sample"))
        XCTAssertEqual(index.schemaVersion, 1)
        XCTAssertEqual(index.plugins.count, 3)
        XCTAssertTrue(index.featured.isEmpty)
        let plugin = try XCTUnwrap(index.plugins.first { $0.id == "commit-commands@claude-plugins-official" })
        XCTAssertNil(plugin.publisher)
        XCTAssertTrue(plugin.files.isEmpty)
        XCTAssertNil(plugin.automatic)
        XCTAssertTrue(index.skills.allSatisfy { $0.files.allSatisfy { $0.sha == nil } })
    }

    func testDecodesTheNewFields() throws {
        let index = try IndexDecoding.decode(Fixtures.data("catalog"))
        XCTAssertEqual(index.featured.map(\.id), ["official-tool@anthropic-mp", "lonely/skills:setup", "gone@nowhere"])
        let partner = try XCTUnwrap(index.plugins.first { $0.id == "partner@anthropic-mp" })
        XCTAssertEqual(partner.publisher, .thirdParty)
        XCTAssertEqual(partner.listedByAnthropic, true)
        XCTAssertEqual(partner.automatic?.hooks.first?.command, "\"${CLAUDE_PLUGIN_ROOT}\"/run.sh")
        XCTAssertEqual(partner.automatic?.mcpServers.first?.env, ["DB_TOKEN"])
        XCTAssertEqual(partner.automatic?.mods.first?.command, "./mods/panel.js")
        XCTAssertEqual(partner.starsGained, StarsGained(count: 5, days: 7))
        // A value this build doesn't know decodes as unknown instead of failing the whole catalog.
        XCTAssertEqual(partner.security?.runsCodeAutomatically, [.hooks, .mcpServers, .unknown])
        let skill = try XCTUnwrap(index.skills.first { $0.id == "lonely/skills:setup" })
        XCTAssertEqual(skill.files.first?.sha, String(repeating: "e", count: 40))
        XCTAssertEqual(skill.install.copy.folderName, "setup")
        XCTAssertEqual(skill.frontmatter["allowed-tools"]?.displayText, "Bash, Read")
        XCTAssertEqual(skill.frontmatter["version"]?.displayText, "2")
    }

    func testRefusesANewerSchema() {
        let data = Data(#"{"schema_version": 3, "generated_at": "2027-01-01T00:00:00Z", "skills": "changed"}"#.utf8)
        XCTAssertThrowsError(try IndexDecoding.decode(data)) { error in
            XCTAssertEqual(error as? IndexDecodingError, .unsupportedSchema(3))
        }
    }

    func testRefusesANewerSchemaEvenWhenItDecodes() {
        let data = Data(#"{"schema_version": 4, "generated_at": "2027-01-01T00:00:00Z"}"#.utf8)
        XCTAssertThrowsError(try IndexDecoding.decode(data)) { error in
            XCTAssertEqual(error as? IndexDecodingError, .unsupportedSchema(4))
        }
    }

    func testDecodesSchemaTwoWithDetailsElsewhere() throws {
        let index = try IndexDecoding.decode(Fixtures.data("catalog-v2"))
        XCTAssertFalse(index.hasInlineDetails)
        XCTAssertEqual(index.details?.url, "https://example.com/r/index-1/details-{bucket}.json")
        let skill = try XCTUnwrap(index.skills.first { $0.id == "lonely/skills:setup" })
        XCTAssertTrue(skill.files.isEmpty)
        XCTAssertEqual(skill.fileCount, 2)
        XCTAssertEqual(skill.skillFileSHA, String(repeating: "e", count: 40))
        XCTAssertEqual(skill.security.rules.isEmpty, true)
        XCTAssertTrue(try XCTUnwrap(index.skills.first { $0.id == "weird/plugin-skill" }).folderIsPlugin)
        let partner = try XCTUnwrap(index.skills.first { $0.id == "partner/tool" })
        XCTAssertEqual(partner.security.rules["pipe-to-shell"], RuleTally(count: 1, severity: .high, summary: "pipe-to-shell summary"))
    }

    func testUnknownRiskSortsAsMostSevere() {
        XCTAssertLessThan(RiskLevel.high, RiskLevel.unknown)
        XCTAssertEqual([RiskLevel.unknown, .low, .high, .medium].sorted(), [.low, .medium, .high, .unknown])
    }
}
