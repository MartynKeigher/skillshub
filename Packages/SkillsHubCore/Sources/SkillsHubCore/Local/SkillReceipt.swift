import Foundation

/// A small file SkillsHub writes inside a skill folder it installs: where the skill came from
/// and the hash of each file it installed. It travels with the folder, so SkillsHub keeps no
/// state of its own, and it's how updates and local edits are detected.
public struct SkillReceipt: Codable, Sendable, Hashable {
    public static let fileName = ".skillshub.json"
    public static let currentVersion = 1

    public var version: Int
    /// The index's skill ID, `owner/repo:path`.
    public var id: String
    public var repo: String
    public var path: String
    public var commit: String
    public var installedAt: Date
    /// Folder-relative path to git blob SHA-1, for every file installed.
    public var files: [String: String]
    /// Set when an existing folder was linked to its source instead of installed by SkillsHub.
    public var adopted: Bool

    public init(id: String, repo: String, path: String, commit: String, installedAt: Date,
                files: [String: String], adopted: Bool = false) {
        version = Self.currentVersion
        self.id = id
        self.repo = repo
        self.path = path
        self.commit = commit
        self.installedAt = installedAt
        self.files = files
        self.adopted = adopted
    }

    public static func read(from folder: URL) -> SkillReceipt? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? decoder.decode(SkillReceipt.self, from: data)
    }

    public func write(to folder: URL) throws {
        try Self.encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
