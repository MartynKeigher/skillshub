import AppKit
import SkillsHubCore
import SwiftUI

/// Shown when Claude Code isn't installed. Browsing works without it; installing needs it,
/// because plugins are installed through the real `claude` CLI.
struct SetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "terminal").font(.system(size: 34)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text("Set Up Claude Code").font(.title.bold())
                    Text("You can browse everything without it. Installing skills and plugins needs it.")
                        .foregroundStyle(.secondary)
                }
            }
            step(1, "Open Terminal and run the official installer:") {
                CommandText("curl -fsSL https://claude.ai/install.sh | bash")
            }
            Text("Or, if you use Homebrew:").font(.callout).foregroundStyle(.secondary).padding(.leading, 32)
            CommandText("brew install --cask claude-code").padding(.leading, 32)
            step(2, "Start it once and sign in, so it sets itself up:") {
                CommandText("claude")
            }
            step(3, "Come back here and check again.") {
                EmptyView()
            }
            Text("Claude Code also needs git, which macOS installs with the Command Line Tools if it's missing.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("Claude Code setup guide", destination: URL(string: "https://code.claude.com/docs/en/setup")!)
                Spacer()
                Button("Open Terminal") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
                Button("Close") { dismiss() }
                Button {
                    checking = true
                    Task {
                        await app.refreshLocal(relocateClaude: true)
                        checking = false
                        if app.local.claude.isReady { dismiss() }
                    }
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text("Check Again") }
                }
                .keyboardShortcut(.defaultAction)
            }
            if !checking, app.local.claude == .notInstalled {
                Text("Still not found. If you installed it somewhere unusual, set its path in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number)")
                    .font(.callout.bold())
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
                Text(text)
            }
            content().padding(.leading, 32)
        }
    }
}
