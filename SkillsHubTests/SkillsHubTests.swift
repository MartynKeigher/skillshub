import SkillsHubCore
import XCTest
@testable import SkillsHub

final class SkillsHubTests: XCTestCase {
    func testGzipRoundTrip() throws {
        // `printf 'hello\n' | gzip -9 -n`
        let gz = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x03, 0xCB, 0x48, 0xCD, 0xC9, 0xC9,
                       0xE7, 0x02, 0x00, 0x20, 0x30, 0x3A, 0x36, 0x06, 0x00, 0x00, 0x00])
        XCTAssertEqual(try Gzip.decompress(gz), Data("hello\n".utf8))
        XCTAssertThrowsError(try Gzip.decompress(Data("not gzip".utf8)))
    }

    func testBundledCatalogDecodes() throws {
        let bundled = BundledCatalog.make(bundle: Bundle(for: AppModel.self))
        XCTAssertNotNil(bundled.generatedAt, "index.meta.json ships with the app")
        let data = try XCTUnwrap(bundled.load(), "index.json.gz ships with the app")
        let catalog = try Catalog(index: IndexDecoding.decode(data))
        XCTAssertEqual(catalog.index.generatedAt, bundled.generatedAt)
        XCTAssertGreaterThan(catalog.items.count, 100)
    }
}
