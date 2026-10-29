import SkillsHubCore
import SwiftUI

extension RiskLevel {
    var title: String {
        switch self {
        case .low: String(localized: "Low risk")
        case .medium: String(localized: "Medium risk")
        case .high: String(localized: "High risk")
        case .unknown: String(localized: "Not reviewed")
        }
    }

    var shortTitle: String {
        switch self {
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .unknown: String(localized: "Not reviewed")
        }
    }

    /// Color is never the only signal: each level also has its own symbol and text.
    var icon: String {
        switch self {
        case .low: "checkmark.shield.fill"
        case .medium: "exclamationmark.triangle.fill"
        case .high: "xmark.octagon.fill"
        case .unknown: "questionmark.diamond.fill"
        }
    }

    var color: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        case .unknown: .gray
        }
    }

    var explanation: String {
        switch self {
        case .low:
            String(localized: "The scan found nothing that needs a closer look. It's a heuristic, not a guarantee.")
        case .medium:
            String(localized: "Bundles scripts, runs code automatically, or has patterns worth reading before you install.")
        case .high:
            String(localized: "Contains code that matches a high-risk pattern, such as piping a download into a shell or reading credentials. Read the findings before you install.")
        case .unknown:
            String(localized: "SkillsFlow couldn't fetch this item's files, so nothing was reviewed and it can't be installed from SkillsHub.")
        }
    }
}

struct RiskBadge: View {
    let risk: RiskLevel
    var compact = false

    var body: some View {
        Label(compact ? risk.shortTitle : risk.title, systemImage: risk.icon)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(risk.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(risk.color.opacity(0.12), in: Capsule())
            .help(risk.explanation)
            .accessibilityLabel(risk.title)
    }
}

extension TrustLabel {
    var icon: String {
        switch self {
        case .anthropic: "checkmark.seal.fill"
        case .anthropicMarketplace: "storefront"
        case .community: "person.2"
        }
    }
}

struct TrustBadge: View {
    let trust: TrustLabel

    var body: some View {
        Label(trust.title, systemImage: trust.icon)
            .font(.caption)
            .foregroundStyle(trust == .anthropic ? Color.accentColor : .secondary)
            .help(trust.explanation)
    }
}

struct KindBadge: View {
    let kind: ItemKind

    var body: some View {
        Label(kind.title, systemImage: kind.icon)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct InstallStateBadge: View {
    let state: InstallState

    var body: some View {
        switch state {
        case .notInstalled:
            EmptyView()
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        case .updateAvailable:
            Label("Update", systemImage: "arrow.down.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
        }
    }
}

/// The square icon a card or row leads with: the kind of item, tinted by its category.
struct ItemIcon: View {
    let item: CatalogItem
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: item.kind.icon)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var tint: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan, .brown]
        let hash = item.category.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}

extension Int {
    /// 12,345 → "12.3K".
    var compactFormatted: String {
        formatted(.number.notation(.compactName).precision(.fractionLength(0 ... 1)))
    }
}

extension Int64 {
    var byteFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
