import Foundation

/// A skill or plugin as the catalog lists it: what a card, row or search needs.
public struct CatalogItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let kind: ItemKind
    public let name: String
    public let summary: String
    /// Plugin author, or the repository owner.
    public let author: String
    public let repo: String?
    public let category: String
    public let tags: [String]
    public let stars: Int?
    public let starsGained: StarsGained?
    public let trust: TrustLabel
    public let security: SecuritySummary
    public let firstSeen: String
    public let added: String?
    /// Plugins whose files SkillsFlow couldn't fetch. They can't be reviewed, so they can't be installed.
    public let isReviewable: Bool

    public var risk: RiskLevel { security.risk }

    /// Lower-cased text that search matches against, built once.
    let searchName: String
    let searchBody: String
}

/// An index turned into what the app browses: items, lookups and the relations between
/// skills and plugins. Built off the main actor once per index.
public struct Catalog: Sendable {
    public let index: CatalogIndex
    public let items: [CatalogItem]
    public let skillsByID: [String: IndexSkill]
    public let pluginsByID: [String: IndexPlugin]
    public let marketplacesByName: [String: IndexMarketplace]
    let itemsByID: [String: CatalogItem]
    /// The earliest `first_seen` in the index: the day SkillsFlow first ran. Everything
    /// already in that run shares it, so it says nothing about when an item is from.
    public let baselineDate: String

    public init(index: CatalogIndex) {
        self.index = index
        let skillsByID = Dictionary(index.skills.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pluginsByID = Dictionary(index.plugins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.skillsByID = skillsByID
        self.pluginsByID = pluginsByID
        marketplacesByName = Dictionary(index.marketplaces.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let anthropicMarketplaces = Set(index.marketplaces.filter {
            $0.publisher.map { $0 == .anthropic } ?? TrustLabel.isAnthropicRepo($0.repo)
        }.map(\.name))

        var items: [CatalogItem] = []
        items.reserveCapacity(index.skills.count + index.plugins.count)
        for plugin in index.plugins {
            let skills = plugin.skills.compactMap { skillsByID[$0] }
            items.append(Self.item(plugin, skills: skills, anthropicMarketplaces: anthropicMarketplaces))
        }
        for skill in index.skills {
            let listed = skill.plugins.contains { pluginsByID[$0].map { anthropicMarketplaces.contains($0.marketplace) } ?? false }
            items.append(Self.item(skill, listedFallback: listed))
        }
        self.items = items
        itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        baselineDate = (index.skills.map(\.firstSeen) + index.plugins.map(\.firstSeen)).filter { !$0.isEmpty }.min() ?? ""
    }

    public func item(id: String) -> CatalogItem? { itemsByID[id] }

    /// The plugins that load a skill, the one to suggest first: reviewed, then lowest risk,
    /// then fewest skills, so installing the skill brings as little else as possible.
    public func plugins(containing skillID: String) -> [IndexPlugin] {
        (skillsByID[skillID]?.plugins ?? []).compactMap { pluginsByID[$0] }.sorted { lhs, rhs in
            let l = itemsByID[lhs.id], r = itemsByID[rhs.id]
            if (l?.isReviewable ?? false) != (r?.isReviewable ?? false) { return l?.isReviewable ?? false }
            if l?.risk != r?.risk { return (l?.risk ?? .unknown) < (r?.risk ?? .unknown) }
            if lhs.skills.count != rhs.skills.count { return lhs.skills.count < rhs.skills.count }
            return lhs.id < rhs.id
        }
    }

    public func skills(of plugin: IndexPlugin) -> [IndexSkill] {
        plugin.skills.compactMap { skillsByID[$0] }
    }

    private static func item(_ skill: IndexSkill, listedFallback: Bool) -> CatalogItem {
        let owner = skill.repo.split(separator: "/").first.map(String.init) ?? skill.repo
        return CatalogItem(
            id: skill.id, kind: .skill, name: skill.name, summary: skill.description, author: owner,
            repo: skill.repo, category: skill.category, tags: [], stars: skill.stars, starsGained: skill.starsGained,
            trust: TrustLabel.make(publisher: skill.publisher, listedByAnthropic: skill.listedByAnthropic,
                                   fallbackRepo: skill.repo, fallbackListed: listedFallback),
            security: .skill(skill), firstSeen: skill.firstSeen, added: skill.added, isReviewable: true,
            searchName: skill.name.lowercased(),
            searchBody: [skill.description, skill.repo, skill.category].joined(separator: " ").lowercased()
        )
    }

    private static func item(_ plugin: IndexPlugin, skills: [IndexSkill], anthropicMarketplaces: Set<String>) -> CatalogItem {
        let name = plugin.displayName ?? plugin.name
        let sourceRepo = plugin.repo ?? plugin.source.repo
        let author = plugin.author ?? sourceRepo?.split(separator: "/").first.map(String.init) ?? plugin.marketplace
        return CatalogItem(
            id: plugin.id, kind: .plugin, name: name, summary: plugin.description ?? "", author: author,
            repo: sourceRepo, category: plugin.category, tags: plugin.tags, stars: plugin.stars,
            starsGained: plugin.starsGained,
            trust: TrustLabel.make(publisher: plugin.publisher, listedByAnthropic: plugin.listedByAnthropic,
                                   fallbackRepo: sourceRepo, fallbackListed: anthropicMarketplaces.contains(plugin.marketplace)),
            security: .plugin(plugin, skills: skills), firstSeen: plugin.firstSeen, added: plugin.added,
            isReviewable: plugin.indexed,
            searchName: ([name, plugin.name] + (plugin.manifestName.map { [$0] } ?? [])).joined(separator: " ").lowercased(),
            searchBody: ([plugin.description ?? "", author, sourceRepo ?? "", plugin.marketplace, plugin.category]
                + plugin.tags).joined(separator: " ").lowercased()
        )
    }
}
