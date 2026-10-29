import Foundation

/// Where Claude Code keeps its files. `CLAUDE_CONFIG_DIR` moves `~/.claude`, and
/// `CLAUDE_CODE_PLUGIN_CACHE_DIR` moves the plugins folder, so both are read from the user's
/// login environment rather than assumed.
public struct ClaudePaths: Sendable, Equatable {
    public let configDirectory: URL
    public let pluginsDirectory: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = [:]) {
        configDirectory = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude")
        pluginsDirectory = environment["CLAUDE_CODE_PLUGIN_CACHE_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? configDirectory.appendingPathComponent("plugins")
    }

    /// `~/.claude/skills`, where personal skills live.
    public var personalSkills: URL { configDirectory.appendingPathComponent("skills") }

    public var installedPluginsFile: URL { pluginsDirectory.appendingPathComponent("installed_plugins.json") }

    /// `<project>/.claude/skills`.
    public static func projectSkills(in project: URL) -> URL {
        project.appendingPathComponent(".claude/skills")
    }
}
