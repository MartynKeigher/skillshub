import Foundation
import Observation
import SkillsHubCore

/// What the window is showing: the sidebar selection, search, sort and filters, and the items
/// that result. Results are memoized, so typing doesn't re-sort the whole catalog on every key.
@MainActor
@Observable
final class CatalogViewModel {
    var selection: SidebarSelection = .discover(.home) {
        didSet {
            guard oldValue != selection else { return }
            searchText = ""
            path = []
            sort = Self.defaultSort(for: selection)
        }
    }

    var searchText = "" {
        didSet { scheduleSearch() }
    }

    /// The search the results use, applied shortly after typing stops.
    private(set) var appliedSearch = ""
    var sort: CatalogSort = .popular
    var filter = CatalogFilter()
    /// Items opened from the list, as a navigation stack.
    var path: [String] = []

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var cache: (key: String, items: [CatalogItem])?

    init(app: AppModel) {
        self.app = app
    }

    var catalog: Catalog? { app.index.catalog }

    var snapshot: LocalSnapshot? {
        catalog.map { app.local.snapshot(for: $0) }
    }

    var isSearching: Bool { !appliedSearch.isEmpty }

    /// Sections that show a fixed ranking, where sorting doesn't apply.
    var isRanked: Bool {
        guard !isSearching else { return false }
        switch selection {
        case .discover(.featured), .discover(.trending), .discover(.popular): return true
        default: return false
        }
    }

    func open(_ item: CatalogItem) {
        path.append(item.id)
    }

    /// The items for the current selection, search, filter and sort.
    var items: [CatalogItem] {
        guard let catalog else { return [] }
        let key = [catalog.index.generatedAt, selection.id, appliedSearch, sort.rawValue, "\(filter)",
                   "\(app.local.revision)"].joined(separator: "§")
        if let cache, cache.key == key { return cache.items }
        let items = compute(catalog)
        cache = (key, items)
        return items
    }

    private func compute(_ catalog: Catalog) -> [CatalogItem] {
        if isSearching {
            return catalog.items(matching: appliedSearch, filter: filter, sort: sort)
        }
        switch selection {
        case .discover(.home):
            return []
        case .discover(.featured):
            return catalog.featured.map(\.item).filter { filter.matches($0) }
        case .discover(.trending):
            return catalog.trending(limit: 200, perRepo: 3, filter: filter)
        case .discover(.popular):
            return catalog.popular(limit: 200, perRepo: 5, filter: filter)
        case .discover(.recentlyAdded):
            return catalog.sorted(catalog.recentlyAdded(within: 90, filter: filter), by: sort)
        case let .kind(kind):
            var scoped = filter
            scoped.kind = kind
            return catalog.items(matching: "", filter: scoped, sort: sort)
        case let .category(name):
            var scoped = filter
            scoped.category = name
            return catalog.items(matching: "", filter: scoped, sort: sort)
        case .library(.installed):
            return libraryItems(catalog) { $0 != .notInstalled }
        case .library(.updates):
            return libraryItems(catalog) { $0 == .updateAvailable }
        case .library(.unlinked):
            return []
        }
    }

    private func libraryItems(_ catalog: Catalog, where include: (InstallState) -> Bool) -> [CatalogItem] {
        guard let snapshot else { return [] }
        let installed = catalog.items.filter { filter.matches($0) && include(snapshot.state(of: $0).state) }
        return catalog.sorted(installed, by: sort)
    }

    var updatesCount: Int {
        guard let catalog, let snapshot else { return 0 }
        return catalog.items.reduce(0) { $0 + (snapshot.state(of: $1).state == .updateAvailable ? 1 : 0) }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            appliedSearch = ""
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.appliedSearch = text
        }
    }

    static func defaultSort(for selection: SidebarSelection) -> CatalogSort {
        switch selection {
        case .discover(.recentlyAdded): .newest
        case .discover(.trending): .trending
        case .library: .name
        default: .popular
        }
    }
}
