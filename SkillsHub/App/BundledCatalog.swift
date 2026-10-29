import Foundation
import SkillsHubCore

/// The catalog that ships inside the app (`Resources/index.json.gz`), so SkillsHub opens
/// instantly and works offline. `Scripts/update_bundled_catalog.sh` refreshes it before a release.
nonisolated enum BundledCatalog {
    static func make(bundle: Bundle = .main) -> BundledIndex {
        BundledIndex(generatedAt: generatedAt(bundle: bundle)) {
            guard let url = bundle.url(forResource: "index.json", withExtension: "gz"),
                  let data = try? Data(contentsOf: url)
            else { return nil }
            return try? Gzip.decompress(data)
        }
    }

    /// From `index.meta.json`, written next to the catalog, so the app can compare it with the
    /// cache without decompressing and decoding the whole thing.
    private static func generatedAt(bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "index.meta", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(IndexCache.Metadata.self, from: data)
        else { return nil }
        return meta.generatedAt
    }
}

/// Reads gzip files with Foundation's raw-DEFLATE decoder, so no extra dependency is needed.
nonisolated enum Gzip {
    struct FormatError: Error {}

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { throw FormatError() }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard bytes.count > offset + 2 else { throw FormatError() }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        if flags & 0x08 != 0 { offset = try skipZeroTerminated(bytes, from: offset) } // FNAME
        if flags & 0x10 != 0 { offset = try skipZeroTerminated(bytes, from: offset) } // FCOMMENT
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset < bytes.count - 8 else { throw FormatError() }
        let deflated = Data(bytes[offset ..< bytes.count - 8])
        return try (deflated as NSData).decompressed(using: .zlib) as Data
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        guard let end = bytes[start...].firstIndex(of: 0) else { throw FormatError() }
        return end + 1
    }
}

/// Downloads `index.json.gz` and unpacks it, a sixth of the size of `index.json`. Releases from
/// before SkillsFlow 0.2 publish only `index.json`, which is used when the compressed one is missing.
nonisolated struct GzipIndexClient: IndexClientProtocol {
    static let latestURL = URL(string: "https://github.com/MartynKeigher/skillsflow/releases/latest/download/index.json.gz")!

    private let compressed = IndexClient(url: GzipIndexClient.latestURL)
    private let plain = IndexClient()

    func fetchLatest(etag: String?) async throws -> IndexFetchResult {
        do {
            switch try await compressed.fetchLatest(etag: etag) {
            case .notModified:
                return .notModified
            case let .updated(data, etag):
                return try .updated(data: Gzip.decompress(data), etag: etag)
            }
        } catch let error as IndexClient.HTTPError where error.statusCode == 404 {
            return try await plain.fetchLatest(etag: etag)
        }
    }
}
