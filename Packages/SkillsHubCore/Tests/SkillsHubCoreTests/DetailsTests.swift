import XCTest
@testable import SkillsHubCore

/// Serves the fixture shards the pipeline wrote, keyed by bucket.
struct FixtureDetailsClient: DetailsClientProtocol {
    let shards: [String: [String: ItemDetail]]

    static func load() throws -> FixtureDetailsClient {
        try FixtureDetailsClient(shards: JSONDecoder().decode([String: [String: ItemDetail]].self,
                                                              from: Fixtures.data("details-v2")))
    }

    func shard(_ bucket: String, catalog: CatalogIndex) async throws -> [String: ItemDetail] {
        guard let shard = shards[bucket] else { throw DetailsError.gone }
        return shard
    }
}

struct FailingDetailsClient: DetailsClientProtocol {
    func shard(_ bucket: String, catalog: CatalogIndex) async throws -> [String: ItemDetail] {
        XCTFail("a version 1 catalog must not fetch shards")
        return [:]
    }
}

final class DetailsTests: XCTestCase {
    func testBucketMatchesThePipeline() throws {
        let client = try FixtureDetailsClient.load()
        let catalog = try Fixtures.catalog("catalog-v2")
        for item in catalog.items {
            XCTAssertNotNil(client.shards[Catalog.detailBucket(for: item.id)]?[item.id], item.id)
        }
    }

    func testDigestMatchesThePipeline() throws {
        let client = try FixtureDetailsClient.load()
        let catalog = try Fixtures.catalog("catalog-v2")
        for skill in catalog.index.skills {
            let detail = try XCTUnwrap(client.shards[Catalog.detailBucket(for: skill.id)]?[skill.id])
            let hashes = Dictionary(uniqueKeysWithValues: detail.files.map { ($0.path, $0.sha!) })
            XCTAssertEqual(FilesDigest.of(hashes), skill.filesDigest, skill.id)
            XCTAssertEqual(skill.fileCount, detail.files.count)
        }
    }

    func testPluginDetailsCombineItsOwnFilesAndItsSkills() async throws {
        let catalog = try Fixtures.catalog("catalog-v2")
        let item = try XCTUnwrap(catalog.item(id: "official-tool@anthropic-mp"))
        let details = try await catalog.details(of: item, using: FixtureDetailsClient.load())
        XCTAssertEqual(details.files.map(\.path), [".claude-plugin/plugin.json", "skills/fmt/SKILL.md"])
        let skillFile = try XCTUnwrap(details.files.last)
        XCTAssertEqual(skillFile.remote.path, "plugins/official-tool/skills/fmt/SKILL.md")
        XCTAssertEqual(skillFile.remote.repo, "anthropics/mp")
        XCTAssertEqual(skillFile.skillID, "anthropics/mp:plugins/official-tool/skills/fmt")
        XCTAssertEqual(details.files.first?.remote.path, "plugins/official-tool/.claude-plugin/plugin.json")
    }

    func testFindingsAreLocatedInsideThePlugin() async throws {
        let catalog = try Fixtures.catalog("catalog-v2")
        let item = try XCTUnwrap(catalog.item(id: "partner@anthropic-mp"))
        let details = try await catalog.details(of: item, using: FixtureDetailsClient.load())
        // The plugin's own finding, then those of the skill at the plugin's root.
        XCTAssertEqual(Set(details.findings.map(\.path)), ["server.js", "run.sh", "SKILL.md"])
        XCTAssertEqual(details.findings(in: "run.sh").first?.finding.rule, "pipe-to-shell")
        XCTAssertTrue(details.findings(in: "run.sh").first?.isInCode ?? false)
        // A skill from another repository keeps its own path.
        XCTAssertTrue(details.files.contains { $0.path == "skills/shared/SKILL.md" && $0.remote.repo == "someone/indie" })
    }

    func testVersionOneCatalogsUseInlineDetails() async throws {
        let catalog = try Fixtures.catalog()
        let item = try XCTUnwrap(catalog.item(id: "lonely/skills:setup"))
        let details = try await catalog.details(of: item, using: FailingDetailsClient())
        XCTAssertEqual(details.files.map(\.path), ["SKILL.md", "scripts/go.py"])
        XCTAssertEqual(details.files.last?.remote.path, "setup/scripts/go.py")
    }

    func testAShardFromAnotherReleaseIsRejected() async throws {
        let catalog = try Fixtures.catalog("catalog-v2")
        let id = "lonely/skills:setup"
        let stale = FixtureDetailsClient(shards: [Catalog.detailBucket(for: id): [id: ItemDetail(commit: "other", files: [], findings: [])]])
        do {
            _ = try await catalog.details(of: XCTUnwrap(catalog.item(id: id)), using: stale)
            XCTFail("expected stale")
        } catch {
            XCTAssertEqual(error as? DetailsError, .stale)
        }
    }

    func testDetailBucketVector() {
        // hashlib.sha1(b"hooky@acme").hexdigest()[:2] in the pipeline's test
        XCTAssertEqual(Catalog.detailBucket(for: "hooky@acme"), "57")
    }
}
