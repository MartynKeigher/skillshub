import AppKit
import Foundation
import SkillsHubCore
import SwiftUI

/// Skill folders that aren't linked to the catalog: identical copies that can be adopted, and
/// folders SkillsHub doesn't recognize.
struct UnlinkedFoldersView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let catalog = app.index.catalog {
            let snapshot = app.local.snapshot(for: catalog)
            let folders = snapshot.folders.filter { folder in
                switch snapshot.folderStatus[folder.id] {
                case .linked, .linkedNotInCatalog: false
                default: true
                }
            }
            if folders.isEmpty {
                ContentUnavailableView("Every Skill Folder Is Accounted For", systemImage: "checkmark.circle",
                                       description: Text("Skill folders that didn't come from the catalog appear here."))
            } else {
                List(folders) { folder in
                    FolderRow(folder: folder, status: snapshot.folderStatus[folder.id] ?? .unknown, catalog: catalog)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct FolderRow: View {
    let folder: LocalSkillFolder
    let status: LocalSkillStatus
    let catalog: Catalog

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: folder.isPlugin ? "puzzlepiece.extension" : "folder")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(folder.name).font(.headline)
                    Text(folder.location.title).font(.caption).foregroundStyle(.secondary)
                }
                Text(folder.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(statusText).font(.callout)
                if !folder.hasSkillFile {
                    Label("No SKILL.md, so Claude Code doesn't load it.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if folder.isPlugin {
                    Label("Has a plugin manifest, so Claude Code loads it as a plugin.", systemImage: "puzzlepiece.extension")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                .buttonStyle(.link)
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch status {
        case let .matches(id):
            let source = catalog.skillsByID[id].map { "\($0.repo)\($0.path.isEmpty ? "" : "/\($0.path)")" } ?? id
            return String(localized: "Identical to \(source). It can be linked to its source to track updates in the next version.")
        case let .resembles(ids):
            return String(localized: "Same name as \(ids.count) catalog skills, but different contents, so it may be edited or from elsewhere.")
        case .unknown:
            return String(localized: "Not from the catalog.")
        case .linked, .linkedNotInCatalog:
            return ""
        }
    }
}
