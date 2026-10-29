import Foundation

/// Who made an item, and whether it's in one of Anthropic's marketplaces. Shown on every card.
///
/// Being listed in Anthropic's marketplace doesn't mean Anthropic made or reviewed the item:
/// most of what those marketplaces list comes from partners and other authors.
public enum TrustLabel: String, Sendable, Hashable, CaseIterable {
    /// Made by Anthropic.
    case anthropic
    /// Made by someone else, listed in a marketplace Anthropic owns.
    case anthropicMarketplace
    /// Neither.
    case community

    public var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .anthropicMarketplace: "Anthropic's marketplace"
        case .community: "Community"
        }
    }

    public var explanation: String {
        switch self {
        case .anthropic:
            "Made by Anthropic."
        case .anthropicMarketplace:
            "Listed in one of Anthropic's marketplaces. Most items there are made by partners and other authors, so check who made it."
        case .community:
            "Made and published by the community. Not listed in Anthropic's marketplaces."
        }
    }

    /// Owners whose repositories count as Anthropic's when the index predates `publisher`.
    static let anthropicOwners: Set<String> = ["anthropics"]

    static func make(publisher: Publisher?, listedByAnthropic: Bool?, fallbackRepo: String?,
                     fallbackListed: Bool) -> TrustLabel {
        let madeByAnthropic: Bool
        if let publisher, publisher != .unknown {
            madeByAnthropic = publisher == .anthropic
        } else {
            madeByAnthropic = isAnthropicRepo(fallbackRepo)
        }
        if madeByAnthropic { return .anthropic }
        return (listedByAnthropic ?? fallbackListed) ? .anthropicMarketplace : .community
    }

    static func isAnthropicRepo(_ slug: String?) -> Bool {
        guard let owner = slug?.split(separator: "/").first else { return false }
        return anthropicOwners.contains(owner.lowercased())
    }
}
