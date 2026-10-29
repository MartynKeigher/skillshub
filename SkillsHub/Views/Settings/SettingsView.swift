import AppKit
import SkillsHubCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintbrush") }
            LocationsSettings().tabItem { Label("Locations", systemImage: "folder") }
            ClaudeSettings().tabItem { Label("Claude Code", systemImage: "terminal") }
            CatalogSettings().tabItem { Label("Catalog", systemImage: "books.vertical") }
        }
        .frame(width: 560)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.system.rawValue
    @AppStorage(ViewMode.storageKey) private var viewMode: ViewMode = .grid

    var body: some View {
        Form {
            Picker("Theme", selection: $theme) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            Picker("Show items as", selection: $viewMode) {
                ForEach(ViewMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        }
        .formStyle(.grouped)
        .onChange(of: theme) { _, new in AppTheme.apply(new) }
    }
}

private struct LocationsSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section {
                LabeledContent("Personal skills") {
                    Text(app.local.paths.personalSkills.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            } footer: {
                Text("Skills here load in every project.")
            }
            Section {
                ForEach(app.local.projectFolders, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder")
                        Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        Spacer()
                        Button(role: .destructive) { app.removeProjectFolder(url) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Stop scanning this project")
                    }
                }
                Button("Add Project Folder…") { chooseProject() }
            } header: {
                Text("Projects")
            } footer: {
                Text("SkillsHub reads each project's .claude/skills folder, so skills committed to a repository show as installed.")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose project folders. SkillsHub reads their .claude/skills folders.")
        if panel.runModal() == .OK {
            panel.urls.forEach(app.addProjectFolder)
        }
    }
}

private struct ClaudeSettings: View {
    @Environment(AppModel.self) private var app
    @State private var customPath = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") { Text(status) }
                if let path = app.local.claude.executable?.path {
                    LabeledContent("Location") {
                        Text(path).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if let issue = app.local.pluginListIssue {
                    Text(issue).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("Custom path", text: $customPath, prompt: Text("Found automatically"))
                    .onSubmit(apply)
                HStack {
                    Button("Choose…") { choose() }
                    Spacer()
                    Button("Check Again") { apply() }
                }
            } footer: {
                Text("SkillsHub looks in the usual places and in your shell's PATH. Set a path only if it can't find claude.")
            }
        }
        .formStyle(.grouped)
        .onAppear { customPath = app.customClaudePath }
    }

    private var status: String {
        switch app.local.claude {
        case .unknown: String(localized: "Checking…")
        case .notInstalled: String(localized: "Not installed")
        case let .outdated(version, _):
            String(localized: "\(version.description). SkillsHub needs \(ClaudeVersion.minimumSupported.description) or later: run `claude update`.")
        case let .broken(_, message): String(localized: "Not responding: \(message)")
        case let .ready(version, _): String(localized: "\(version.description), ready")
        }
    }

    private func apply() {
        app.customClaudePath = customPath
        Task { await app.refreshLocal(relocateClaude: true) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            customPath = url.path
            apply()
        }
    }
}

private struct CatalogSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section {
                LabeledContent("Generated") { Text(app.index.generatedAt ?? "—") }
                LabeledContent("Source") { Text(source) }
                if let generator = app.index.catalog?.index.generator {
                    LabeledContent("Built by") { Text(generator) }
                }
                if let error = app.index.lastRefreshError {
                    LabeledContent("Last refresh") { Text(error).foregroundStyle(.secondary) }
                }
                HStack {
                    Spacer()
                    Button("Refresh Now") { Task { await app.refreshCatalog() } }
                        .disabled(app.index.isRefreshing)
                }
            } footer: {
                Text("The catalog comes from SkillsFlow, which crawls skill repositories and plugin marketplaces daily and scans each item. SkillsHub ships with a copy and refreshes it in the background.")
            }
        }
        .formStyle(.grouped)
    }

    private var source: String {
        switch app.index.source {
        case .none: String(localized: "Not loaded")
        case .bundled: String(localized: "Built into the app")
        case .cached: String(localized: "Downloaded earlier")
        case .downloaded: String(localized: "Downloaded now")
        }
    }
}
