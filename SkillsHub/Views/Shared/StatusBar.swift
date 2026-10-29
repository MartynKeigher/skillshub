import Foundation
import SkillsHubCore
import SwiftUI

struct StatusBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 14) {
            if let catalog = app.index.catalog {
                Text("\(catalog.index.skills.count.formatted()) skills · \(catalog.index.plugins.count.formatted()) plugins")
                Text("Catalog \(catalogDate(catalog.index.generatedAt))\(sourceSuffix)")
                    .help(app.index.lastRefreshError ?? "")
            }
            if app.index.isRefreshing || app.local.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            if app.index.lastRefreshError != nil {
                Label("Offline", systemImage: "wifi.slash").help(app.index.lastRefreshError ?? "")
            }
            Spacer()
            claudeStatus
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    @ViewBuilder
    private var claudeStatus: some View {
        switch app.local.claude {
        case .unknown:
            Text("Looking for Claude Code…")
        case .notInstalled:
            Label("Claude Code not installed", systemImage: "exclamationmark.circle")
        case let .outdated(version, _):
            Label("Claude Code \(version.description) is too old to manage plugins", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case let .broken(_, message):
            Label("Claude Code didn't respond", systemImage: "exclamationmark.triangle").help(message)
        case let .ready(version, executable):
            Label("Claude Code \(version.description)", systemImage: "checkmark.circle").help(executable.path)
        }
    }

    private var sourceSuffix: String {
        switch app.index.source {
        case .bundled: String(localized: " (built in)")
        case .cached, .downloaded, .none: ""
        }
    }

    private func catalogDate(_ iso: String) -> String {
        guard let date = try? Date(iso, strategy: .iso8601) else { return iso }
        return date.formatted(.relative(presentation: .named))
    }
}
