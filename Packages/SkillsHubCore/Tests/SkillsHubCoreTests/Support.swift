import Foundation
@testable import SkillsHubCore

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrapURL(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func catalog(_ name: String = "catalog") throws -> Catalog {
        try Catalog(index: IndexDecoding.decode(data(name)))
    }

    private static func XCTUnwrapURL(_ url: URL?) throws -> URL {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        return url
    }
}

/// A fresh temporary folder, removed when the test case ends.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("skillshub-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}
