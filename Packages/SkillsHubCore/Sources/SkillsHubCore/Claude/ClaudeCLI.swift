import Foundation

public struct ClaudeVersion: Sendable, Comparable, Hashable, CustomStringConvertible {
    /// `plugin` subcommands print JSON results from this version on.
    public static let minimumSupported = ClaudeVersion(2, 1, 268)

    public let major: Int, minor: Int, patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `claude --version` output such as `2.1.312 (Claude Code)`.
    public init?(parsing output: String) {
        guard let token = output.split(whereSeparator: \.isWhitespace).first else { return nil }
        let parts = token.split(separator: ".").map { Int($0) }
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else { return nil }
        self.init(major, minor, patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ClaudeVersion, rhs: ClaudeVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct ClaudeCLIError: LocalizedError, Equatable {
    public let command: String
    public let message: String

    public var errorDescription: String? { "`claude \(command)` failed: \(message)" }
}

/// Runs the real `claude` binary, so everything SkillsHub does matches the terminal.
public protocol ClaudeCLIProtocol: Sendable {
    func version() async throws -> ClaudeVersion
    func listPlugins() async throws -> [InstalledPlugin]
}

public struct ClaudeCLI: ClaudeCLIProtocol {
    public let executable: URL
    private let environment: [String: String]
    private let runner: any ProcessRunning

    public init(executable: URL, environment: [String: String], runner: any ProcessRunning = SystemProcessRunner()) {
        self.executable = executable
        self.environment = environment
        self.runner = runner
    }

    public func version() async throws -> ClaudeVersion {
        let output = try await run(["--version"])
        guard let version = ClaudeVersion(parsing: output) else {
            throw ClaudeCLIError(command: "--version", message: "unexpected output \(output.prefix(80))")
        }
        return version
    }

    public func listPlugins() async throws -> [InstalledPlugin] {
        let output = try await run(["plugin", "list", "--json"])
        return try JSONDecoder().decode([InstalledPlugin].self, from: Data(Self.jsonArray(in: output).utf8))
    }

    private func run(_ arguments: [String]) async throws -> String {
        let output = try await runner.run(executable, arguments: arguments, environment: environment,
                                          currentDirectory: nil, timeout: .seconds(60))
        guard output.exitCode == 0 else {
            let message = output.stderr.isEmpty ? output.stdout : output.stderr
            throw ClaudeCLIError(command: arguments.joined(separator: " "),
                                 message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.stdout
    }

    /// The JSON array in the output, skipping any notices printed before it.
    static func jsonArray(in output: String) -> String {
        guard let start = output.range(of: "\n[")?.lowerBound ?? (output.hasPrefix("[") ? output.startIndex : nil),
              let end = output.lastIndex(of: "]")
        else { return "[]" }
        return String(output[start ... end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
