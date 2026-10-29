import XCTest
@testable import SkillsHubCore

final class HashingAndContentTests: XCTestCase {
    override func setUp() {
        StubURLProtocol.reset()
    }

    func testGitBlobHashMatchesGit() throws {
        // `git hash-object` of an empty file and of "hello\n".
        XCTAssertEqual(GitBlobHash.of(Data()), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
        XCTAssertEqual(GitBlobHash.of(Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
        let dir = try makeTemporaryDirectory()
        let big = Data((0 ..< 3_000_000).map { UInt8($0 % 251) })
        try big.write(to: dir.appendingPathComponent("big.bin"))
        XCTAssertEqual(try GitBlobHash.ofFile(at: dir.appendingPathComponent("big.bin")), GitBlobHash.of(big))
    }

    func testSHA1KnownVectors() {
        var abc = SHA1()
        abc.update(Data("abc".utf8))
        XCTAssertEqual(abc.hexDigest(), "a9993e364706816aba3e25717850c26c9cd0d89d")
        var long = SHA1()
        long.update(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
        XCTAssertEqual(long.hexDigest(), "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    }

    func testRawURLEncodesEachSegment() {
        let file = RemoteFile(repo: "a/b", commit: "c0ffee", path: "skills/my skill/#notes.md", size: 1, sha: nil)
        XCTAssertEqual(file.rawURL.absoluteString, "https://raw.githubusercontent.com/a/b/c0ffee/skills/my%20skill/%23notes.md")
    }

    func testContentIsVerifiedAndCached() async throws {
        let body = Data("# Skill\n".utf8)
        let file = RemoteFile(repo: "a/b", commit: "c1", path: "SKILL.md", size: Int64(body.count), sha: GitBlobHash.of(body))
        StubURLProtocol.responses[file.rawURL.absoluteString] = .init(body: body)
        let client = ContentClient(session: StubURLProtocol.session(), cacheDirectory: try makeTemporaryDirectory())
        let first = try await client.contents(of: file)
        let second = try await client.contents(of: file)
        XCTAssertEqual(first, body)
        XCTAssertEqual(second, body)
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "the second read comes from the cache")
    }

    func testContentThatDoesNotMatchTheCatalogIsRejected() async throws {
        let file = RemoteFile(repo: "a/b", commit: "c1", path: "run.sh", size: 5, sha: GitBlobHash.of(Data("safe\n".utf8)))
        StubURLProtocol.responses[file.rawURL.absoluteString] = .init(body: Data("evil\n".utf8))
        let client = ContentClient(session: StubURLProtocol.session(), cacheDirectory: nil)
        do {
            _ = try await client.contents(of: file)
            XCTFail("expected a hash mismatch")
        } catch let error as ContentError {
            guard case .hashMismatch = error else { return XCTFail("\(error)") }
        }
    }

    func testFilesDigestOrdersPathsByUTF8Bytes() {
        // "B" (0x42) sorts before "a" (0x61) by bytes, as in the pipeline.
        var sha = SHA1()
        sha.update(Data("B\0\(String(repeating: "2", count: 40))\na\0\(String(repeating: "1", count: 40))\n".utf8))
        XCTAssertEqual(FilesDigest.of(["a": String(repeating: "1", count: 40), "B": String(repeating: "2", count: 40)]),
                       sha.hexDigest())
    }
}
