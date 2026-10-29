import Foundation
import SkillsHubCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: CatalogViewModel

    var body: some View {
        List(selection: selection) {
            Section("Discover") {
                ForEach(DiscoverItem.allCases) { item in
                    Label(item.title, systemImage: item.icon).tag(SidebarSelection.discover(item))
                }
            }
            Section("Browse") {
                ForEach(ItemKind.allCases, id: \.self) { kind in
                    Label(kind.pluralTitle, systemImage: kind.icon).tag(SidebarSelection.kind(kind))
                }
            }
            Section("Library") {
                ForEach(LibraryItem.allCases) { item in
                    Label(item.title, systemImage: item.icon)
                        .badge(item == .updates ? model.updatesCount : 0)
                        .tag(SidebarSelection.library(item))
                }
            }
            if let catalog = app.index.catalog {
                Section("Categories") {
                    ForEach(catalog.categoryCounts, id: \.category) { entry in
                        Label(entry.category, systemImage: Self.icon(for: entry.category))
                            .badge(entry.count)
                            .tag(SidebarSelection.category(entry.category))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selection: Binding<SidebarSelection?> {
        Binding(get: { model.selection }, set: { if let value = $0 { model.selection = value } })
    }

    static func icon(for category: String) -> String {
        switch category {
        case "Documents": "doc.richtext"
        case "Security": "lock.shield"
        case "DevOps & Cloud": "cloud"
        case "Data & Analytics": "chart.bar"
        case "Design": "paintpalette"
        case "Writing & Content": "pencil.line"
        case "Marketing & Sales": "megaphone"
        case "AI & Agents": "sparkles"
        case "Testing": "checkmark.diamond"
        case "Development": "chevron.left.forwardslash.chevron.right"
        case "Productivity": "bolt"
        case "Research & Learning": "books.vertical"
        default: "square.grid.2x2"
        }
    }
}
