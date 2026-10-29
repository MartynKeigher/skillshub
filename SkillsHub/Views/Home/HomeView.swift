import SkillsHubCore
import SwiftUI

/// Featured picks first, then shelves that each lead to their full list.
struct HomeView: View {
    @Bindable var model: CatalogViewModel

    var body: some View {
        if let catalog = model.catalog {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    let featured = catalog.featured.filter { model.filter.matches($0.item) }
                    if !featured.isEmpty {
                        Shelf(title: "Featured", destination: .discover(.featured), model: model,
                              entries: featured.map { ShelfEntry(item: $0.item, note: $0.note) })
                    }
                    shelf("Trending", .discover(.trending), catalog.trending(limit: 12, filter: model.filter))
                    shelf("Popular", .discover(.popular), catalog.popular(limit: 12, filter: model.filter))
                    shelf("Recently Added", .discover(.recentlyAdded),
                          catalog.recentlyAdded(within: 30, limit: 12, filter: model.filter))
                    CategoryGrid(model: model, counts: catalog.categoryCounts)
                }
                .padding(20)
            }
            .navigationTitle("Home")
        }
    }

    @ViewBuilder
    private func shelf(_ title: LocalizedStringKey, _ destination: SidebarSelection, _ items: [CatalogItem]) -> some View {
        if !items.isEmpty {
            Shelf(title: title, destination: destination, model: model, entries: items.map { ShelfEntry(item: $0, note: nil) })
        }
    }
}

private struct ShelfEntry: Identifiable {
    let item: CatalogItem
    let note: String?

    var id: String { item.id }
}

private struct Shelf: View {
    let title: LocalizedStringKey
    let destination: SidebarSelection
    let model: CatalogViewModel
    let entries: [ShelfEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title2.bold())
                Spacer()
                Button("See All") { model.selection = destination }
                    .buttonStyle(.link)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(entries) { entry in
                        Button { model.open(entry.item) } label: {
                            ItemCard(item: entry.item,
                                     state: model.snapshot?.state(of: entry.item).state ?? .notInstalled,
                                     note: entry.note)
                                .frame(width: 290)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct CategoryGrid: View {
    let model: CatalogViewModel
    let counts: [(category: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(counts, id: \.category) { entry in
                    Button { model.selection = .category(entry.category) } label: {
                        HStack {
                            Image(systemName: SidebarView.icon(for: entry.category))
                                .frame(width: 22)
                                .foregroundStyle(Color.accentColor)
                            Text(entry.category)
                            Spacer()
                            Text(entry.count.compactFormatted).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
