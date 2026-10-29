import Foundation

public enum CatalogSort: String, CaseIterable, Identifiable, Sendable {
    case popular, trending, newest, name

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .popular: "Most Stars"
        case .trending: "Trending"
        case .newest: "Newest"
        case .name: "Name"
        }
    }
}

public struct CatalogFilter: Sendable, Hashable {
    public var kind: ItemKind?
    public var category: String?
    /// Show only items at or below this level.
    public var maximumRisk: RiskLevel?
    public var trust: TrustLabel?

    public init(kind: ItemKind? = nil, category: String? = nil, maximumRisk: RiskLevel? = nil, trust: TrustLabel? = nil) {
        self.kind = kind
        self.category = category
        self.maximumRisk = maximumRisk
        self.trust = trust
    }

    public func matches(_ item: CatalogItem) -> Bool {
        if let kind, item.kind != kind { return false }
        if let category, item.category != category { return false }
        if let maximumRisk, item.risk > maximumRisk { return false }
        if let trust, item.trust != trust { return false }
        return true
    }
}

extension Catalog {
    /// Items matching the filter and search text, best match first when searching.
    public func items(matching text: String, filter: CatalogFilter = .init(), sort: CatalogSort = .popular) -> [CatalogItem] {
        let terms = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let filtered = items.filter(filter.matches)
        guard !terms.isEmpty else { return sorted(filtered, by: sort) }
        let scored: [(CatalogItem, Int)] = filtered.compactMap { item in
            var score = 0
            for term in terms {
                if item.searchName == term {
                    score += 100
                } else if item.searchName.hasPrefix(term) {
                    score += 40
                } else if item.searchName.contains(term) {
                    score += 20
                } else if item.searchBody.contains(term) {
                    score += 5
                } else {
                    return nil // every term must match somewhere
                }
            }
            return (item, score)
        }
        let rank = Dictionary(uniqueKeysWithValues: sorted(scored.map(\.0), by: sort).enumerated().map { ($1.id, $0) })
        return scored.sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 > rhs.1 : rank[lhs.0.id, default: 0] < rank[rhs.0.id, default: 0]
        }.map(\.0)
    }

    public func sorted(_ items: [CatalogItem], by sort: CatalogSort) -> [CatalogItem] {
        switch sort {
        case .popular:
            items.sorted { ($0.stars ?? -1, $1.name) > ($1.stars ?? -1, $0.name) }
        case .trending:
            items.sorted { (Self.trendScore($0), $1.name) > (Self.trendScore($1), $0.name) }
        case .newest:
            items.sorted { (addedDate(of: $0) ?? "", $1.name) > (addedDate(of: $1) ?? "", $0.name) }
        case .name:
            items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: Home sections

    /// The curated picks, in the index's order.
    public var featured: [(item: CatalogItem, note: String?)] {
        index.featured.compactMap { pick in item(id: pick.id).map { (item: $0, note: pick.note) } }
    }

    /// Most stars gained per day recently. At most `perRepo` items from one repository, since
    /// every skill in a repository shares its stars.
    public func trending(limit: Int = 20, perRepo: Int = 2, filter: CatalogFilter = .init()) -> [CatalogItem] {
        let rising = items.filter { filter.matches($0) && ($0.starsGained?.count ?? 0) > 0 }
        return Self.capped(sorted(rising, by: .trending), perRepo: perRepo, limit: limit)
    }

    /// Most stars overall, at most `perRepo` items from one repository.
    public func popular(limit: Int = 20, perRepo: Int = 3, filter: CatalogFilter = .init()) -> [CatalogItem] {
        Self.capped(sorted(items.filter { filter.matches($0) && $0.stars != nil }, by: .popular), perRepo: perRepo, limit: limit)
    }

    /// Items added within `days` of `now`, newest first.
    public func recentlyAdded(within days: Int, now: Date = .now, limit: Int? = nil, filter: CatalogFilter = .init()) -> [CatalogItem] {
        let cutoff = Self.dayString(Calendar.utc.date(byAdding: .day, value: -days, to: now) ?? now)
        let recent = items.filter { filter.matches($0) && (addedDate(of: $0).map { $0 >= cutoff } ?? false) }
        let result = sorted(recent, by: .newest)
        return limit.map { Array(result.prefix($0)) } ?? result
    }

    /// When an item was added: its git date when SkillsFlow found one, else the day it first
    /// appeared in the index, unless that's the first run's date, which every older item shares.
    public func addedDate(of item: CatalogItem) -> String? {
        if let added = item.added { return added }
        return item.firstSeen > baselineDate ? item.firstSeen : nil
    }

    public var categoryCounts: [(category: String, count: Int)] {
        let counts = Dictionary(grouping: items, by: \.category).mapValues(\.count)
        let ordered = index.categories.isEmpty ? counts.keys.sorted() : index.categories
        return ordered.compactMap { name in counts[name].map { (category: name, count: $0) } }
    }

    // MARK: Helpers

    static func trendScore(_ item: CatalogItem) -> Double {
        guard let gained = item.starsGained, gained.count > 0 else { return 0 }
        return Double(gained.count) / Double(max(gained.days, 1))
    }

    static func capped(_ items: [CatalogItem], perRepo: Int, limit: Int) -> [CatalogItem] {
        var perRepoCount: [String: Int] = [:]
        var result: [CatalogItem] = []
        for item in items {
            let key = item.repo?.lowercased() ?? item.id
            guard perRepoCount[key, default: 0] < perRepo else { continue }
            perRepoCount[key, default: 0] += 1
            result.append(item)
            if result.count == limit { break }
        }
        return result
    }

    static func dayString(_ date: Date) -> String {
        let c = Calendar.utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
