//
//  AppTheme.swift
//  SkillsHub
//
//  Adapted from CaskHub's AppTheme.swift (https://github.com/alielsokary/CaskHub),
//  Copyright (c) 2026 Ali Elsokary, MIT License. See THIRD_PARTY_NOTICES.md.
//

import AppKit
import Foundation

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    static let storageKey = "appTheme"

    var id: String { rawValue }

    /// `rawValue` stays language-independent because it's persisted.
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    static func apply(_ raw: String) {
        let app = NSApplication.shared
        switch AppTheme(rawValue: raw) ?? .system {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case grid, list

    static let storageKey = "viewMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: String(localized: "Grid")
        case .list: String(localized: "List")
        }
    }

    var icon: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}
