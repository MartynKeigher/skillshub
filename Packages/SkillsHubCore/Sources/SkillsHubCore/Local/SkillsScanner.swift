import Foundation

/// Where a skills folder is.
public enum SkillLocation: Sendable, Hashable {
    /// `~/.claude/skills`, loaded in every project.
    case personal
    /// `<project>/.claude/skills`, for a project folder the user added.
    case project(URL)

    public var title: String {
        switch self {
        case .personal: "Personal"
        case let .project(url): url.lastPathComponent
        }
    }
}

public struct SkillsRoot: Sendable, Hashable {
    public let location: SkillLocation
    /// The `skills` folder itself.
    public let url: URL

    public init(location: SkillLocation, url: URL) {
        self.location = location
        self.url = url
    }
}

/// One folder inside a skills folder.
public struct LocalSkillFolder: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public let location: SkillLocation
    public let url: URL
    public let name: String
    public let hasSkillFile: Bool
    /// The folder is a symbolic link to somewhere else; Claude Code follows it.
    public let isLink: Bool
    /// Has `.claude-plugin/plugin.json`: Claude Code loads it as `<name>@skills-dir`.
    public let isPlugin: Bool
    public let receipt: SkillReceipt?
    /// Git blob SHA-1 of `SKILL.md`, used to match an unlinked folder to the catalog.
    public let skillFileHash: String?
    /// Frontmatter `name` from `SKILL.md`, which sets the command when present.
    public let declaredName: String?

    public init(location: SkillLocation, url: URL, name: String, hasSkillFile: Bool, isLink: Bool, isPlugin: Bool,
                receipt: SkillReceipt?, skillFileHash: String?, declaredName: String?) {
        self.location = location
        self.url = url
        self.name = name
        self.hasSkillFile = hasSkillFile
        self.isLink = isLink
        self.isPlugin = isPlugin
        self.receipt = receipt
        self.skillFileHash = skillFileHash
        self.declaredName = declaredName
    }
}

public protocol SkillsScanning: Sendable {
    func scan(_ roots: [SkillsRoot]) async -> [LocalSkillFolder]
}

/// Reads skills folders straight from disk, the way Claude Code finds them.
public struct FileSystemSkillsScanner: SkillsScanning {
    /// Claude Code keeps skills synced from claude.ai here; they aren't the user's to manage.
    static let reservedNames: Set<String> = ["synced", "anthropic-skills"]

    public init() {}

    public func scan(_ roots: [SkillsRoot]) async -> [LocalSkillFolder] {
        await Self.scanOffMain(roots)
    }

    @concurrent private static func scanOffMain(_ roots: [SkillsRoot]) async -> [LocalSkillFolder] {
        let fm = FileManager.default
        var folders: [LocalSkillFolder] = []
        for root in roots {
            guard let names = try? fm.contentsOfDirectory(atPath: root.url.path) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") && !reservedNames.contains(name.lowercased()) {
                let url = root.url.appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                let isLink = (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
                let skillFile = url.appendingPathComponent("SKILL.md")
                let hasSkillFile = fm.fileExists(atPath: skillFile.path)
                folders.append(LocalSkillFolder(
                    location: root.location, url: url, name: name, hasSkillFile: hasSkillFile, isLink: isLink,
                    isPlugin: fm.fileExists(atPath: url.appendingPathComponent(".claude-plugin/plugin.json").path),
                    receipt: SkillReceipt.read(from: url),
                    skillFileHash: hasSkillFile ? try? GitBlobHash.ofFile(at: skillFile) : nil,
                    declaredName: hasSkillFile ? Self.frontmatterName(of: skillFile) : nil
                ))
            }
        }
        return folders
    }

    /// The `name:` line of the YAML frontmatter, without a YAML parser.
    static func frontmatterName(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 8192), let text = String(data: head, encoding: .utf8) else { return nil }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        guard lines.next()?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        while let line = lines.next() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if trimmed.hasPrefix("name:") {
                let value = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }
}
