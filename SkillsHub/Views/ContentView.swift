import Foundation
import SkillsHubCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: CatalogViewModel
    @AppStorage(ViewMode.storageKey) private var viewMode: ViewMode = .grid
    @State private var showsSetup = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            NavigationStack(path: $model.path) {
                page
                    .navigationDestination(for: String.self) { id in
                        ItemDetailView(id: id, catalogModel: model)
                    }
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search skills and plugins")
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
        .sheet(isPresented: $showsSetup) { SetupView() }
        .task { await app.start() }
    }

    @ViewBuilder
    private var page: some View {
        if app.index.catalog == nil {
            ProgressView("Opening the catalog…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.selection == .discover(.home) && !model.isSearching {
            HomeView(model: model)
        } else if model.selection == .library(.unlinked) && !model.isSearching {
            UnlinkedFoldersView()
        } else {
            CatalogListView(model: model)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if case .notInstalled = app.local.claude {
                Button {
                    showsSetup = true
                } label: {
                    Label("Set Up Claude Code", systemImage: "exclamationmark.circle")
                }
                .help("Claude Code isn't installed. Browsing works without it; installing needs it.")
            }
            FilterMenu(filter: $model.filter, showsKind: !isKindPage)
            if !model.isRanked && model.selection != .discover(.home) {
                Picker("Sort", selection: $model.sort) {
                    ForEach(CatalogSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Sort")
            }
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Show as grid or list")
            Button {
                Task {
                    await app.refreshCatalog()
                    await app.refreshLocal()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(app.index.isRefreshing || app.local.isRefreshing)
            .help("Refresh the catalog and what's installed")
        }
    }

    private var isKindPage: Bool {
        if case .kind = model.selection { return true }
        return false
    }
}

struct FilterMenu: View {
    @Binding var filter: CatalogFilter
    var showsKind = true

    var body: some View {
        Menu {
            if showsKind {
                Picker("Kind", selection: $filter.kind) {
                    Text("Skills and Plugins").tag(ItemKind?.none)
                    ForEach(ItemKind.allCases, id: \.self) { Text($0.pluralTitle).tag(ItemKind?.some($0)) }
                }
            }
            Picker("Risk", selection: $filter.maximumRisk) {
                Text("Any Risk").tag(RiskLevel?.none)
                Text("Low Only").tag(RiskLevel?.some(.low))
                Text("Low and Medium").tag(RiskLevel?.some(.medium))
            }
            Picker("Source", selection: $filter.trust) {
                Text("Any Source").tag(TrustLabel?.none)
                ForEach(TrustLabel.allCases, id: \.self) { Text($0.title).tag(TrustLabel?.some($0)) }
            }
            if isActive {
                Divider()
                Button("Clear Filters") { filter = CatalogFilter(category: filter.category) }
            }
        } label: {
            Label("Filter", systemImage: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Filter by kind, risk and source")
    }

    private var isActive: Bool {
        filter.kind != nil || filter.maximumRisk != nil || filter.trust != nil
    }
}
