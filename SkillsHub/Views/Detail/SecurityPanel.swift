import SkillsHubCore
import SwiftUI

/// The first thing on every item's page after its header: how risky it looks, what it runs
/// on its own, and each finding, linked to the line it's on.
struct SecurityPanel: View {
    let item: CatalogItem
    let catalog: Catalog
    let model: DetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Security").font(.title2.bold())
            riskSummary
            if !item.security.wasReviewed {
                Callout(icon: "questionmark.diamond.fill", color: .gray,
                        title: "Not reviewed",
                        message: "SkillsFlow couldn't fetch this plugin's files, so nothing about it was scanned.")
            }
            if item.security.skillFolderIsPlugin {
                Callout(icon: "puzzlepiece.extension.fill", color: .orange,
                        title: "This skill folder is also a plugin",
                        message: "It has a .claude-plugin/plugin.json. Copied into ~/.claude/skills, Claude Code loads it as a plugin, including any hooks or servers it declares.")
            }
            if let plugin = catalog.pluginsByID[item.id], let automatic = plugin.automatic, !automatic.isEmpty {
                AutomaticSection(automatic: automatic)
            } else if !item.security.runsAutomatically.isEmpty {
                Callout(icon: "gearshape.2.fill", color: .orange,
                        title: "Runs code automatically",
                        message: "Once enabled, this plugin starts \(item.security.runsAutomatically.map(\.title).formatted(.list(type: .and))) without Claude choosing to.")
            }
            FindingsSection(item: item, model: model)
            Text("The scan looks for risky patterns. It can't prove anything is safe or malicious, so read the files that matter to you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(item.risk.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(item.risk.color.opacity(0.35))
        }
    }

    private var riskSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.risk.icon)
                .font(.system(size: 30))
                .foregroundStyle(item.risk.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.risk.title).font(.title3.bold())
                Text(item.risk.explanation).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    if item.security.scripts > 0 {
                        Label("\(item.security.scripts) scripts", systemImage: "terminal")
                    }
                    if item.security.binaries > 0 {
                        Label("\(item.security.binaries) binary files", systemImage: "cpu")
                    }
                    if item.security.findingCount > 0 {
                        Label("\(item.security.findingCount) findings", systemImage: "magnifyingglass")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}

extension AutomaticKind {
    var title: String {
        switch self {
        case .hooks: String(localized: "hooks")
        case .mcpServers: String(localized: "MCP servers")
        case .lspServers: String(localized: "LSP servers")
        case .monitors: String(localized: "monitors")
        case .mods: String(localized: "mods")
        case .bin: String(localized: "executables")
        case .unknown: String(localized: "other components")
        }
    }
}

private struct Callout: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Every command the plugin starts on its own once enabled, as SkillsFlow read it.
private struct AutomaticSection: View {
    let automatic: AutomaticComponents

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Runs code automatically", systemImage: "gearshape.2.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("These start once the plugin is enabled, without Claude choosing a skill, and run with your user's permissions.")
                .font(.callout)
                .foregroundStyle(.secondary)
            group("Hooks", automatic.hooks) { hook in
                [hook.event, hook.matcher.map { "matching \($0)" }, hook.type.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            }
            group("MCP servers", automatic.mcpServers) { server in
                [server.name, server.type.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            }
            group("LSP servers", automatic.lspServers) { $0.name ?? "" }
            group("Monitors", automatic.monitors) { $0.name ?? "" }
            group("Mods (JavaScript that runs inside Claude Code)", automatic.mods) { _ in "" }
            if !automatic.bin.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Executables Claude can run").font(.subheadline.bold())
                    Text(automatic.bin.joined(separator: ", "))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ entries: [AutomaticEntry],
                       caption: @escaping (AutomaticEntry) -> String) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold())
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        let label = caption(entry)
                        if !label.isEmpty {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                        }
                        CommandText(entry.command)
                        if !entry.env.isEmpty {
                            Text("Environment: \(entry.env.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let file = entry.file {
                            Text("Declared in \(file)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

/// Findings grouped by rule. The catalog's summary shows at once; each finding's file, line and
/// excerpt appear when the item's details arrive.
private struct FindingsSection: View {
    let item: CatalogItem
    let model: DetailViewModel

    var body: some View {
        let rules = item.security.rules
        if rules.isEmpty {
            if item.security.wasReviewed {
                Label("No findings.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Findings").font(.headline)
                ForEach(rules) { rule in
                    DisclosureGroup {
                        findings(for: rule.rule)
                    } label: {
                        HStack {
                            Image(systemName: rule.severity.icon).foregroundStyle(rule.severity.color)
                            Text(rule.summary)
                            Spacer()
                            Text("\(rule.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func findings(for rule: String) -> some View {
        switch model.details {
        case let .loaded(details):
            ForEach(Array(details.findings.filter { $0.finding.rule == rule }.enumerated()), id: \.offset) { _, located in
                Button { model.open(located) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(located.path + (located.finding.line.map { ":\($0)" } ?? ""))
                                .font(.system(.callout, design: .monospaced))
                            ContextTag(context: located.finding.context)
                            Spacer()
                        }
                        if let excerpt = located.finding.excerpt {
                            Text(excerpt)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show in the file")
            }
        case .loading, .idle:
            ProgressView().controlSize(.small)
        case let .failed(message):
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ContextTag: View {
    let context: FindingContext

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .help(help)
    }

    private var title: String {
        switch context {
        case .code: String(localized: "code")
        case .comment: String(localized: "comment")
        case .documentation: String(localized: "docs")
        case .file: String(localized: "file")
        case .unknown: String(localized: "other")
        }
    }

    private var help: String {
        switch context {
        case .code: String(localized: "In code that can run.")
        case .comment: String(localized: "In a code comment, which doesn't run.")
        case .documentation: String(localized: "In Markdown that Claude reads as instructions. Prose often warns against a pattern, so it counts one level lower.")
        case .file: String(localized: "About the whole file.")
        case .unknown: ""
        }
    }
}
