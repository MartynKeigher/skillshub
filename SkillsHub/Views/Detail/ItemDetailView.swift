import AppKit
import SkillsHubCore
import SwiftUI

struct ItemDetailView: View {
    @Environment(AppModel.self) private var app
    let catalogModel: CatalogViewModel
    @State private var model: DetailViewModel?
    private let id: String

    init(id: String, catalogModel: CatalogViewModel) {
        self.id = id
        self.catalogModel = catalogModel
    }

    var body: some View {
        Group {
            if let catalog = app.index.catalog, let item = catalog.item(id: id), let model {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        DetailHeader(item: item, catalog: catalog, state: catalogModel.snapshot?.state(of: item) ?? .none,
                                     open: { catalogModel.path.append($0) })
                        SecurityPanel(item: item, catalog: catalog, model: model)
                        AboutSection(item: item, catalog: catalog)
                        if item.kind == .plugin, let plugin = catalog.pluginsByID[item.id] {
                            PluginSkillsSection(plugin: plugin, catalog: catalog, open: { catalogModel.path.append($0) })
                        }
                        ContentsSection(model: model)
                    }
                    .padding(24)
                    .frame(maxWidth: 1100, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .navigationTitle(item.name)
                .task(id: id) { await model.loadDetails() }
            } else if app.index.catalog != nil {
                ContentUnavailableView("Not in the Catalog", systemImage: "questionmark.square.dashed",
                                       description: Text("This item isn't in the current catalog."))
            }
        }
        .onAppear {
            if model == nil { model = DetailViewModel(itemID: id, app: app) }
        }
    }
}

// MARK: Header and install

private struct DetailHeader: View {
    let item: CatalogItem
    let catalog: Catalog
    let state: ItemLocalState
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ItemIcon(item: item, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(.largeTitle.bold()).textSelection(.enabled)
                    HStack(spacing: 10) {
                        Text(item.author).foregroundStyle(.secondary)
                        if let repo = item.repo, let url = URL(string: "https://github.com/\(repo)") {
                            Link(repo, destination: url).font(.callout)
                        }
                    }
                    HStack(spacing: 12) {
                        KindBadge(kind: item.kind)
                        TrustBadge(trust: item.trust)
                        RiskBadge(risk: item.risk)
                        InstallStateBadge(state: state.state)
                    }
                }
                Spacer(minLength: 0)
            }
            if !item.summary.isEmpty {
                Text(item.summary).font(.title3).textSelection(.enabled)
            }
            Text(item.trust.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
            InstallSection(item: item, catalog: catalog, state: state, open: open)
        }
    }
}

/// Where the item is installed, or how it would be. Installing from SkillsHub comes in the
/// next milestone; until then the page shows what an install would do and the terminal commands.
private struct InstallSection: View {
    let item: CatalogItem
    let catalog: Catalog
    let state: ItemLocalState
    let open: (String) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if state.state != .notInstalled {
                    installedDetails
                    Divider()
                }
                switch item.kind {
                case .plugin: pluginInstall
                case .skill: skillInstall
                }
                Text("Installing from SkillsHub, after a full review of every file, comes in the next version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label(state.state == .notInstalled ? "Install" : "Installed", systemImage: "arrow.down.circle")
        }
    }

    @ViewBuilder
    private var installedDetails: some View {
        if state.state == .updateAvailable {
            Label("An update is available.", systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
        }
        ForEach(state.folders) { folder in
            HStack {
                Label(folder.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
                    .textSelection(.enabled)
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                    .buttonStyle(.link)
            }
        }
        ForEach(state.pluginInstalls) { install in
            Label("\(install.pluginID), \(install.scope.rawValue) scope, version \(install.version)\(install.enabled ? "" : ", disabled")",
                  systemImage: "puzzlepiece.extension")
        }
        if state.isProjectScopedOnly {
            Text("Installed for a project. SkillsHub manages user-scope installs; project installs are shown for reference.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pluginInstall: some View {
        if let plugin = catalog.pluginsByID[item.id] {
            if !item.isReviewable {
                Label("SkillsFlow couldn't fetch this plugin's files, so it can't be reviewed or installed from SkillsHub.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Text("In Terminal:").font(.callout).foregroundStyle(.secondary)
            if let marketplace = catalog.marketplacesByName[plugin.marketplace] {
                CommandText(marketplace.addCommand)
            }
            CommandText(plugin.installCommand)
        }
    }

    @ViewBuilder
    private var skillInstall: some View {
        let plugins = catalog.plugins(containing: item.id)
        if let first = plugins.first {
            // A skill that belongs to a plugin installs that plugin, so the files it relies on come too.
            VStack(alignment: .leading, spacing: 6) {
                Label("This skill comes with a plugin", systemImage: "puzzlepiece.extension")
                    .font(.headline)
                Text("Installing it installs the plugin \(first.displayName ?? first.name), so the scripts and files the skill relies on are installed with it. Review the plugin too: it may include other skills, hooks or servers.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open \(first.displayName ?? first.name)") { open(first.id) }
                    if plugins.count > 1 {
                        Menu("Other plugins with this skill") {
                            ForEach(plugins.dropFirst(), id: \.id) { plugin in
                                Button(plugin.displayName ?? plugin.id) { open(plugin.id) }
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        } else if let skill = catalog.skillsByID[item.id] {
            Text("Copies the skill folder at commit \(String(skill.commit.prefix(7))) to:")
                .font(.callout).foregroundStyle(.secondary)
            CommandText(skill.install.copy.target)
        }
    }
}

/// A command or path, selectable, with a copy button.
struct CommandText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack {
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Copy")
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: About

private struct AboutSection: View {
    let item: CatalogItem
    let catalog: Catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About").font(.title2.bold())
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.label).foregroundStyle(.secondary)
                        row.value
                    }
                }
            }
        }
    }

    private struct Row: Identifiable {
        let label: String
        let value: AnyView
        var id: String { label }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        func add(_ label: String, _ text: String?) {
            if let text, !text.isEmpty { rows.append(Row(label: label, value: AnyView(Text(text).textSelection(.enabled)))) }
        }
        func link(_ label: String, _ title: String, _ url: String) {
            if let url = URL(string: url) { rows.append(Row(label: label, value: AnyView(Link(title, destination: url)))) }
        }
        let repoInfo = item.repo.flatMap { slug in catalog.index.repos.first { $0.slug.lowercased() == slug.lowercased() } }
        switch item.kind {
        case .skill:
            guard let skill = catalog.skillsByID[item.id] else { return rows }
            link(String(localized: "Source"), skill.repo + (skill.path.isEmpty ? "" : "/\(skill.path)"), skill.url)
            link(String(localized: "Commit"), String(skill.commit.prefix(10)), "https://github.com/\(skill.repo)/commit/\(skill.commit)")
            add(String(localized: "Files"), "\(skill.fileCount) files, \(skill.filesSize.byteFormatted)")
            add(String(localized: "License"), skill.license ?? repoInfo?.license)
            add(String(localized: "Last updated"), Self.date(skill.repoPushedAt ?? repoInfo?.pushedAt))
            for key in ["allowed-tools", "version", "model", "compatibility"] {
                add(key, skill.frontmatter[key]?.displayText)
            }
        case .plugin:
            guard let plugin = catalog.pluginsByID[item.id] else { return rows }
            add(String(localized: "Plugin ID"), plugin.id)
            add(String(localized: "Version"), plugin.version)
            add(String(localized: "Marketplace"), plugin.marketplace)
            if let repo = plugin.repo, let commit = plugin.commit {
                let path = (plugin.path ?? "").isEmpty ? "" : "/\(plugin.path ?? "")"
                link(String(localized: "Source"), repo + path, "https://github.com/\(repo)/tree/\(commit)\(path)")
                link(String(localized: "Commit"), String(commit.prefix(10)), "https://github.com/\(repo)/commit/\(commit)")
            }
            if let homepage = plugin.homepage { link(String(localized: "Homepage"), homepage, homepage) }
            add(String(localized: "License"), plugin.license ?? repoInfo?.license)
            add(String(localized: "Last updated"), Self.date(repoInfo?.pushedAt))
            if !plugin.tags.isEmpty { add(String(localized: "Tags"), plugin.tags.joined(separator: ", ")) }
        }
        if let stars = item.stars { add(String(localized: "Stars"), stars.formatted()) }
        if let gained = item.starsGained, gained.count > 0 {
            add(String(localized: "Recently"), String(localized: "+\(gained.count) stars in \(gained.days) days"))
        }
        add(String(localized: "Category"), item.category)
        add(String(localized: "Added"), catalog.addedDate(of: item).flatMap { Self.date($0) })
        return rows
    }

    static func date(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let day = String(iso.prefix(10))
        guard let date = try? Date(day + "T00:00:00Z", strategy: .iso8601) else { return day }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: Plugin skills

private struct PluginSkillsSection: View {
    let plugin: IndexPlugin
    let catalog: Catalog
    let open: (String) -> Void

    var body: some View {
        let skills = catalog.skills(of: plugin)
        VStack(alignment: .leading, spacing: 10) {
            Text("Included").font(.title2.bold())
            if let components = plugin.components {
                Text(summary(components)).foregroundStyle(.secondary)
            }
            if !skills.isEmpty {
                VStack(spacing: 0) {
                    ForEach(skills, id: \.id) { skill in
                        Button { open(skill.id) } label: {
                            HStack {
                                Image(systemName: ItemKind.skill.icon).foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text("/\(plugin.manifestName ?? plugin.name):\(skill.name)")
                                        .font(.system(.body, design: .monospaced))
                                    Text(skill.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                RiskBadge(risk: catalog.item(id: skill.id)?.risk ?? skill.security.risk, compact: true)
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private func summary(_ c: PluginComponents) -> String {
        var parts: [String] = []
        if c.skills > 0 { parts.append(String(localized: "\(c.skills) skills")) }
        if c.commands > 0 { parts.append(String(localized: "\(c.commands) commands")) }
        if c.agents > 0 { parts.append(String(localized: "\(c.agents) agents")) }
        if c.hooks { parts.append(String(localized: "hooks")) }
        if c.mcpServers { parts.append(String(localized: "MCP servers")) }
        if c.lspServers { parts.append(String(localized: "LSP servers")) }
        if c.monitors { parts.append(String(localized: "monitors")) }
        if c.mods { parts.append(String(localized: "mods")) }
        if c.bin { parts.append(String(localized: "executables")) }
        return parts.isEmpty ? String(localized: "No components found.") : parts.formatted(.list(type: .and))
    }
}
