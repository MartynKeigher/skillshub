//
//  SidebarItem.swift
//  SkillsHub
//
//  Adapted from CaskHub's SidebarItem.swift (https://github.com/alielsokary/CaskHub),
//  Copyright (c) 2026 Ali Elsokary, MIT License. See THIRD_PARTY_NOTICES.md.
//

import SkillsHubCore

enum DiscoverItem: String, CaseIterable, Identifiable {
    case home, featured, trending, popular, recentlyAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .featured: String(localized: "Featured")
        case .trending: String(localized: "Trending")
        case .popular: String(localized: "Popular")
        case .recentlyAdded: String(localized: "Recently Added")
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .featured: "star"
        case .trending: "chart.line.uptrend.xyaxis"
        case .popular: "flame"
        case .recentlyAdded: "clock.badge.checkmark"
        }
    }
}

enum LibraryItem: String, CaseIterable, Identifiable {
    case installed, updates, unlinked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed: String(localized: "Installed")
        case .updates: String(localized: "Updates")
        case .unlinked: String(localized: "Not from the Catalog")
        }
    }

    var icon: String {
        switch self {
        case .installed: "checkmark.circle"
        case .updates: "arrow.triangle.2.circlepath"
        case .unlinked: "questionmark.folder"
        }
    }
}

enum SidebarSelection: Hashable, Identifiable {
    case discover(DiscoverItem)
    case kind(ItemKind)
    case library(LibraryItem)
    case category(String)

    var id: String {
        switch self {
        case let .discover(item): "discover.\(item.rawValue)"
        case let .kind(kind): "kind.\(kind.rawValue)"
        case let .library(item): "library.\(item.rawValue)"
        case let .category(name): "category.\(name)"
        }
    }

    var title: String {
        switch self {
        case let .discover(item): item.title
        case let .kind(kind): kind.pluralTitle
        case let .library(item): item.title
        case let .category(name): name
        }
    }
}

extension ItemKind {
    var title: String {
        switch self {
        case .skill: String(localized: "Skill")
        case .plugin: String(localized: "Plugin")
        }
    }

    var pluralTitle: String {
        switch self {
        case .skill: String(localized: "Skills")
        case .plugin: String(localized: "Plugins")
        }
    }

    var icon: String {
        switch self {
        case .skill: "doc.text"
        case .plugin: "puzzlepiece.extension"
        }
    }
}
