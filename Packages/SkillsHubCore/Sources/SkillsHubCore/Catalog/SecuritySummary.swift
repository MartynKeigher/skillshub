import Foundation

/// What the catalog says about an item's security, combined from the plugin's own scan and the
/// scans of the skills it loads. Available offline; the individual findings, with their files
/// and lines, come with the item's details.
public struct SecuritySummary: Sendable, Hashable {
    /// The worst level across the item and everything it brings. `.unknown` when SkillsFlow
    /// couldn't read the plugin's files, so nothing was reviewed.
    public let risk: RiskLevel
    /// One entry per rule, most severe first.
    public let rules: [RuleSummary]
    public let scripts: Int
    public let binaries: Int
    /// What a plugin starts on its own once enabled.
    public let runsAutomatically: [AutomaticKind]
    /// A skill folder holding `.claude-plugin/plugin.json`. Copied into `~/.claude/skills`,
    /// Claude Code loads it as a plugin, with any hooks and servers it declares.
    public let skillFolderIsPlugin: Bool
    public let wasReviewed: Bool

    public var findingCount: Int { rules.reduce(0) { $0 + $1.count } }

    static func skill(_ skill: IndexSkill) -> SecuritySummary {
        SecuritySummary(
            risk: skill.folderIsPlugin ? max(skill.security.risk, .medium) : skill.security.risk,
            rules: RuleSummary.merge([skill.security.rules]),
            scripts: skill.security.scripts,
            binaries: skill.security.binaries,
            runsAutomatically: [],
            skillFolderIsPlugin: skill.folderIsPlugin,
            wasReviewed: true
        )
    }

    static func plugin(_ plugin: IndexPlugin, skills: [IndexSkill]) -> SecuritySummary {
        guard plugin.indexed, let own = plugin.security else {
            return SecuritySummary(risk: .unknown, rules: [], scripts: 0, binaries: 0, runsAutomatically: [],
                                   skillFolderIsPlugin: false, wasReviewed: false)
        }
        return SecuritySummary(
            risk: skills.map(\.security.risk).reduce(own.risk, max),
            rules: RuleSummary.merge([own.rules] + skills.map(\.security.rules)),
            scripts: skills.reduce(own.scripts) { $0 + $1.security.scripts },
            binaries: skills.reduce(own.binaries) { $0 + $1.security.binaries },
            runsAutomatically: own.runsCodeAutomatically.filter { $0 != .unknown },
            skillFolderIsPlugin: false,
            wasReviewed: true
        )
    }
}

public struct RuleSummary: Sendable, Hashable, Identifiable {
    public var id: String { rule }
    public let rule: String
    public let count: Int
    public let severity: RiskLevel
    public let summary: String

    static func merge(_ tallies: [[String: RuleTally]]) -> [RuleSummary] {
        var merged: [String: RuleSummary] = [:]
        for tally in tallies {
            for (rule, t) in tally {
                let previous = merged[rule]
                merged[rule] = RuleSummary(rule: rule, count: (previous?.count ?? 0) + t.count,
                                           severity: max(previous?.severity ?? .low, t.severity),
                                           summary: previous?.summary ?? t.summary)
            }
        }
        return merged.values.sorted { $0.severity != $1.severity ? $0.severity > $1.severity : $0.rule < $1.rule }
    }
}

/// A finding and where its file sits inside the item being shown.
public struct LocatedFinding: Sendable, Hashable {
    public let finding: Finding
    /// The skill folder's path inside the plugin, or "" for the item's own files.
    public let pathPrefix: String
    public let skillID: String?

    /// The file's path relative to the item: what the contents view lists.
    public var path: String {
        pathPrefix.isEmpty ? finding.file : "\(pathPrefix)/\(finding.file)"
    }

    /// Findings in code, which runs, as opposed to prose or comments that mention a pattern.
    public var isInCode: Bool {
        finding.context == .code || finding.context == .file
    }
}

extension IndexPlugin {
    /// Where a skill's folder sits inside this plugin's folder. Falls back to the skill's
    /// own path when it isn't below the plugin (another repository or commit).
    public func relativePath(of skill: IndexSkill) -> String {
        guard skill.repo.lowercased() == repo?.lowercased(), let root = path else { return skill.path }
        if root.isEmpty { return skill.path }
        if skill.path == root { return "" }
        if skill.path.hasPrefix(root + "/") { return String(skill.path.dropFirst(root.count + 1)) }
        return skill.path
    }
}
