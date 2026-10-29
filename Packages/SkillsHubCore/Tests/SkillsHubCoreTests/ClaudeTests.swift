import XCTest
@testable import SkillsHubCore

/// Answers commands from a table keyed by their arguments.
struct FakeRunner: ProcessRunning {
    var outputs: [String: ProcessOutput]

    func run(_ executable: URL, arguments: [String], environment: [String: String]?, currentDirectory: URL?,
             timeout: Duration?) async throws -> ProcessOutput {
        outputs[arguments.joined(separator: " ")] ?? ProcessOutput(exitCode: 127, stdout: "", stderr: "not found")
    }
}

struct FakeCLI: ClaudeCLIProtocol {
    var installedVersion: ClaudeVersion
    var plugins: [InstalledPlugin]
    var listFails = false

    func version() async throws -> ClaudeVersion { installedVersion }

    func listPlugins() async throws -> [InstalledPlugin] {
        if listFails { throw ClaudeCLIError(command: "plugin list --json", message: "boom") }
        return plugins
    }
}

final class ClaudeTests: XCTestCase {
    func testVersionParsing() {
        XCTAssertEqual(ClaudeVersion(parsing: "2.1.312 (Claude Code)\n"), ClaudeVersion(2, 1, 312))
        XCTAssertNil(ClaudeVersion(parsing: "Claude Code"))
        XCTAssertLessThan(ClaudeVersion(2, 1, 99), ClaudeVersion.minimumSupported)
        XCTAssertGreaterThan(ClaudeVersion(2, 2, 0), ClaudeVersion.minimumSupported)
    }

    func testPluginListJSONFromTheRealCLI() throws {
        // `claude plugin list --json` from Claude Code 2.1.312, with a notice printed first.
        let output = """
        Some notice from the CLI
        [
          {
            "id": "commit-commands@claude-code-plugins",
            "version": "1.0.1",
            "scope": "user",
            "enabled": true,
            "installPath": "/Users/me/.claude/plugins/cache/claude-code-plugins/commit-commands/1.0.1",
            "installedAt": "2026-10-28T13:27:32.127Z",
            "lastUpdated": "2026-10-28T13:27:32.127Z",
            "projectEnabled": true
          }
        ]
        """
        let plugins = try JSONDecoder().decode([InstalledPlugin].self, from: Data(ClaudeCLI.jsonArray(in: output).utf8))
        XCTAssertEqual(plugins.first?.pluginID, "commit-commands@claude-code-plugins")
        XCTAssertEqual(plugins.first?.scope, .user)
        XCTAssertEqual(plugins.first?.marketplace, "claude-code-plugins")
        XCTAssertEqual(ClaudeCLI.jsonArray(in: "[]"), "[]")
        XCTAssertEqual(ClaudeCLI.jsonArray(in: "nothing here"), "[]")
    }

    func testCLIReportsFailures() async {
        let runner = FakeRunner(outputs: ["plugin list --json": ProcessOutput(exitCode: 1, stdout: "", stderr: "bad\n")])
        let cli = ClaudeCLI(executable: URL(fileURLWithPath: "/x/claude"), environment: [:], runner: runner)
        do {
            _ = try await cli.listPlugins()
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ClaudeCLIError, ClaudeCLIError(command: "plugin list --json", message: "bad"))
        }
    }

    func testRecordsReaderReadsTheInstalledCommit() throws {
        let dir = try makeTemporaryDirectory()
        // installed_plugins.json as written by Claude Code 2.1.312.
        try write("""
        {"version": 2, "plugins": {"commit-commands@claude-code-plugins": [{"scope": "user",
          "installPath": "/p", "version": "1.0.1", "installedAt": "2026-10-28T13:27:32.127Z",
          "lastUpdated": "2026-10-28T13:27:32.127Z", "gitCommitSha": "f8c5e7a1dcb71b10cb74586224b5401f3de5db28"}]}}
        """, to: dir.appendingPathComponent("installed_plugins.json"))
        let reader = PluginRecordsReader(file: dir.appendingPathComponent("installed_plugins.json"))
        XCTAssertEqual(reader.records().first?.gitCommitSha, "f8c5e7a1dcb71b10cb74586224b5401f3de5db28")
        XCTAssertEqual(reader.installedPlugins().first?.version, "1.0.1")
        XCTAssertTrue(PluginRecordsReader(file: dir.appendingPathComponent("missing.json")).records().isEmpty)
    }

    func testPathsFollowClaudeEnvironmentVariables() {
        let home = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(ClaudePaths(home: home).personalSkills.path, "/Users/me/.claude/skills")
        let moved = ClaudePaths(home: home, environment: ["CLAUDE_CONFIG_DIR": "/cfg", "CLAUDE_CODE_PLUGIN_CACHE_DIR": "/plug"])
        XCTAssertEqual(moved.personalSkills.path, "/cfg/skills")
        XCTAssertEqual(moved.installedPluginsFile.path, "/plug/installed_plugins.json")
        XCTAssertEqual(ClaudePaths(home: home, environment: ["CLAUDE_CONFIG_DIR": ""]).configDirectory.path, "/Users/me/.claude")
    }

    func testLoginEnvironmentIgnoresWhatTheShellPrints() {
        let output = "Welcome!\n\(ClaudeLocator.marker)PATH=/opt/homebrew/bin:/usr/bin\0HOME=/Users/me\0\(ClaudeLocator.marker)bye"
        XCTAssertEqual(ClaudeLocator.parseEnvironment(output), ["PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/me"])
        XCTAssertNil(ClaudeLocator.parseEnvironment("no markers"))
    }

    func testLocatorPrefersCustomThenKnownThenPATH() async {
        let home = URL(fileURLWithPath: "/Users/me")
        let env = "\(ClaudeLocator.marker)PATH=/custom/bin\0\(ClaudeLocator.marker)"
        let runner = FakeRunner(outputs: ["-i -l -c printf '\(ClaudeLocator.marker)'; env -0; printf '\(ClaudeLocator.marker)'":
                                    ProcessOutput(exitCode: 0, stdout: env, stderr: "")])
        let onPath = ClaudeLocator(home: home, shell: "/bin/zsh", runner: runner, isExecutable: { $0 == "/custom/bin/claude" })
        let found = await onPath.locate()
        XCTAssertEqual(found?.executable.path, "/custom/bin/claude")
        XCTAssertEqual(found?.environment["PATH"], "/custom/bin")

        let native = ClaudeLocator(home: home, shell: "/bin/zsh", runner: runner,
                                   isExecutable: { ["/Users/me/.local/bin/claude", "/custom/bin/claude", "/mine/claude"].contains($0) })
        let nativeFound = await native.locate()
        XCTAssertEqual(nativeFound?.executable.path, "/Users/me/.local/bin/claude")
        let customFound = await native.locate(customPath: "/mine/claude")
        XCTAssertEqual(customFound?.executable.path, "/mine/claude")

        let none = ClaudeLocator(home: home, shell: "/bin/zsh", runner: runner, isExecutable: { _ in false })
        let missing = await none.locate()
        XCTAssertNil(missing)
    }

    func testSystemRunnerRunsAndTimesOut() async throws {
        let runner = SystemProcessRunner()
        let echo = try await runner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf out; printf err >&2; exit 3"])
        XCTAssertEqual(echo, ProcessOutput(exitCode: 3, stdout: "out", stderr: "err"))
        let start = Date()
        do {
            // `sleep` outlives `sh` and holds the pipes: the timeout must still return promptly.
            _ = try await runner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 5; echo late"], environment: nil,
                                     currentDirectory: nil, timeout: .milliseconds(200))
            XCTFail("expected a timeout")
        } catch {
            XCTAssertTrue(error is ProcessTimeoutError)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
