import Foundation

/// Finds the `claude` binary and the environment to run it in.
///
/// Apps opened from the Finder don't inherit the user's shell PATH, so a `claude` installed
/// with npm, or one that needs `node` or `git` from Homebrew, isn't found from the app's own
/// environment. The locator asks the user's login shell, the same way a terminal would.
public struct ClaudeLocator: Sendable {
    public struct Installation: Sendable, Equatable {
        public let executable: URL
        /// The login shell's environment, to run `claude` with.
        public let environment: [String: String]
    }

    private let home: URL
    private let shell: String
    private let runner: any ProcessRunning
    private let isExecutable: @Sendable (String) -> Bool

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
                runner: any ProcessRunning = SystemProcessRunner(),
                isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.home = home
        self.shell = shell
        self.runner = runner
        self.isExecutable = isExecutable
    }

    /// Where the documented installers put `claude`: the native installer, Homebrew, and npm.
    public var knownLocations: [URL] {
        [
            home.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            home.appendingPathComponent(".npm-global/bin/claude"),
        ]
    }

    /// `customPath` is a path the user chose in Settings, tried first.
    public func locate(customPath: String? = nil) async -> Installation? {
        let environment = await loginEnvironment()
        if let customPath, !customPath.isEmpty, isExecutable(customPath) {
            return Installation(executable: URL(fileURLWithPath: customPath), environment: environment)
        }
        if let found = knownLocations.first(where: { isExecutable($0.path) }) {
            return Installation(executable: found, environment: environment)
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("claude")
            if isExecutable(candidate.path) {
                return Installation(executable: candidate, environment: environment)
            }
        }
        return nil
    }

    static let marker = "__SKILLSHUB_ENV__"

    /// The environment of an interactive login shell, so settings from `.zshrc` (where npm,
    /// nvm and Homebrew usually add to PATH) count. Falls back to the app's own environment.
    public func loginEnvironment() async -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        let script = "printf '\(Self.marker)'; env -0; printf '\(Self.marker)'"
        guard let output = try? await runner.run(URL(fileURLWithPath: shell), arguments: ["-i", "-l", "-c", script],
                                                 environment: nil, currentDirectory: home, timeout: .seconds(10)),
              let environment = Self.parseEnvironment(output.stdout), !environment.isEmpty
        else { return current }
        return environment
    }

    /// The `env -0` output between the markers; anything a shell config prints is ignored.
    static func parseEnvironment(_ output: String) -> [String: String]? {
        let parts = output.components(separatedBy: marker)
        guard parts.count >= 3 else { return nil }
        var environment: [String: String] = [:]
        for entry in parts[1].split(separator: "\0") {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        return environment
    }
}
