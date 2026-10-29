import SkillsHubCore
import SwiftUI

@main
struct SkillsHubApp: App {
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.system.rawValue
    @State private var app: AppModel
    @State private var catalog: CatalogViewModel

    init() {
        let app = AppModel()
        _app = State(initialValue: app)
        _catalog = State(initialValue: CatalogViewModel(app: app))
        AppTheme.apply(UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? AppTheme.system.rawValue)
    }

    var body: some Scene {
        Window("SkillsHub", id: "main") {
            ContentView(model: catalog)
                .frame(minWidth: 960, minHeight: 600)
                .environment(app)
                .onChange(of: theme, initial: true) { _, new in AppTheme.apply(new) }
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task {
                        await app.refreshCatalog()
                        await app.refreshLocal()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
