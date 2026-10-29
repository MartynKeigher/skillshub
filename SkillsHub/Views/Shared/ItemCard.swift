import SkillsHubCore
import SwiftUI

struct ItemCard: View {
    let item: CatalogItem
    let state: InstallState
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ItemIcon(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                InstallStateBadge(state: state)
            }
            Text(note ?? item.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
            HStack(spacing: 8) {
                RiskBadge(risk: item.risk, compact: true)
                if !item.security.runsAutomatically.isEmpty {
                    Image(systemName: "gearshape.2.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Runs code automatically once enabled")
                        .accessibilityLabel("Runs code automatically")
                }
                Spacer(minLength: 0)
                if let stars = item.stars {
                    Label(stars.compactFormatted, systemImage: "star")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("GitHub stars of \(item.repo ?? "the repository")")
                }
            }
            HStack {
                KindBadge(kind: item.kind)
                Spacer(minLength: 0)
                TrustBadge(trust: item.trust)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ItemRow: View {
    let item: CatalogItem
    let state: InstallState

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(item: item, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.headline).lineLimit(1)
                    KindBadge(kind: item.kind).labelStyle(.iconOnly)
                }
                Text(item.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            InstallStateBadge(state: state)
            TrustBadge(trust: item.trust)
                .frame(width: 170, alignment: .leading)
            RiskBadge(risk: item.risk, compact: true)
                .frame(width: 110, alignment: .leading)
            Text(item.stars.map(\.compactFormatted) ?? "–")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
