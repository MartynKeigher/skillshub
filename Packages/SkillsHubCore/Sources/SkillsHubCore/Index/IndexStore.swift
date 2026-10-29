import Foundation
import Observation

/// The catalog the app is showing, and where it came from. Opens the newer of the bundled and
/// cached copies, then refreshes from SkillsFlow in the background. Never replaces a catalog
/// with an older one.
@MainActor
@Observable
public final class IndexStore {
    public enum Source: String, Sendable {
        case none, bundled, cached, downloaded
    }

    public private(set) var catalog: Catalog?
    public private(set) var source: Source = .none
    public private(set) var isRefreshing = false
    public private(set) var lastRefreshError: String?
    public private(set) var lastRefreshed: Date?

    public var generatedAt: String? { catalog?.index.generatedAt }

    @ObservationIgnored private let bundled: BundledIndex
    @ObservationIgnored private let cache: IndexCache?
    @ObservationIgnored private let client: any IndexClientProtocol

    public init(bundled: BundledIndex, cache: IndexCache?, client: any IndexClientProtocol) {
        self.bundled = bundled
        self.cache = cache
        self.client = client
    }

    /// Opens the newest local copy. Reads only one of the two from disk.
    public func loadLocal() async {
        guard catalog == nil else { return }
        let cachedMeta = cache?.metadata()
        let preferCache = cachedMeta.map { meta in bundled.generatedAt.map { meta.generatedAt > $0 } ?? true } ?? false
        if preferCache, let cache, let catalog = await Self.decode(loading: { cache.load() }) {
            apply(catalog, from: .cached)
            return
        }
        if let catalog = await Self.decode(loading: bundled.load) {
            apply(catalog, from: .bundled)
        } else if let cache, let catalog = await Self.decode(loading: { cache.load() }) {
            apply(catalog, from: .cached)
        }
    }

    /// Downloads the latest catalog and switches to it when it's newer.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let etag = source == .bundled ? nil : cache?.metadata()?.etag
            switch try await client.fetchLatest(etag: etag) {
            case .notModified:
                break
            case let .updated(data, newEtag):
                let catalog = try await Self.decodeOrThrow(data)
                if catalog.index.generatedAt > (generatedAt ?? "") {
                    apply(catalog, from: .downloaded)
                }
                try? cache?.save(data, metadata: .init(etag: newEtag, generatedAt: catalog.index.generatedAt))
            }
            lastRefreshError = nil
            lastRefreshed = .now
        } catch {
            lastRefreshError = error.localizedDescription
        }
    }

    private func apply(_ catalog: Catalog, from source: Source) {
        self.catalog = catalog
        self.source = source
    }

    // Decoding a 10 MB catalog takes a noticeable moment: keep it off the main actor.
    @concurrent private nonisolated static func decode(loading: @Sendable () -> Data?) async -> Catalog? {
        guard let data = loading() else { return nil }
        return try? Catalog(index: IndexDecoding.decode(data))
    }

    @concurrent private nonisolated static func decodeOrThrow(_ data: Data) async throws -> Catalog {
        try Catalog(index: IndexDecoding.decode(data))
    }
}
