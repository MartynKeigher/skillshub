import SkillsHubCore
import SwiftUI

struct CatalogListView: View {
    @Bindable var model: CatalogViewModel
    @AppStorage(ViewMode.storageKey) private var viewMode: ViewMode = .grid
    /// Items shown so far; more are added when the end scrolls into view.
    @State private var shown = 120

    var body: some View {
        let items = model.items
        Group {
            if items.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptyIcon, description: Text(emptyMessage))
            } else if viewMode == .grid {
                ScrollView {
                    header(count: items.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16)], spacing: 16) {
                        ForEach(items.prefix(shown)) { item in
                            Button { model.open(item) } label: {
                                ItemCard(item: item, state: state(of: item))
                            }
                            .buttonStyle(.plain)
                        }
                        moreMarker(total: items.count)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            } else {
                List {
                    header(count: items.count)
                    ForEach(items.prefix(shown)) { item in
                        Button { model.open(item) } label: {
                            ItemRow(item: item, state: state(of: item))
                        }
                        .buttonStyle(.plain)
                    }
                    moreMarker(total: items.count)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(model.isSearching ? "Search" : model.selection.title)
        .onChange(of: model.items.count) { shown = 120 }
        .onChange(of: model.selection) { shown = 120 }
    }

    private func state(of item: CatalogItem) -> InstallState {
        model.snapshot?.state(of: item).state ?? .notInstalled
    }

    private func header(count: Int) -> some View {
        HStack {
            Text(model.isSearching ? "\(count) results for “\(model.appliedSearch)”" : "\(count) items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, viewMode == .grid ? 20 : 0)
        .padding(.top, viewMode == .grid ? 12 : 0)
    }

    @ViewBuilder
    private func moreMarker(total: Int) -> some View {
        if shown < total {
            ProgressView()
                .frame(maxWidth: .infinity)
                .onAppear { shown += 120 }
        }
    }

    private var emptyTitle: String {
        if model.isSearching { return String(localized: "No Results") }
        switch model.selection {
        case .library(.installed): return String(localized: "Nothing Installed Yet")
        case .library(.updates): return String(localized: "Everything Is Up to Date")
        case .discover(.trending): return String(localized: "Nothing Trending Yet")
        case .discover(.recentlyAdded): return String(localized: "Nothing New")
        default: return String(localized: "Nothing Here")
        }
    }

    private var emptyIcon: String {
        model.isSearching ? "magnifyingglass" : "tray"
    }

    private var emptyMessage: String {
        if model.isSearching { return String(localized: "Try different words, or clear the filters.") }
        switch model.selection {
        case .discover(.trending):
            return String(localized: "Trending needs a few days of star history. Check back soon.")
        case .library(.installed):
            return String(localized: "Skills in ~/.claude/skills, your project folders and installed plugins appear here.")
        default:
            return String(localized: "Try another section, or clear the filters.")
        }
    }
}
