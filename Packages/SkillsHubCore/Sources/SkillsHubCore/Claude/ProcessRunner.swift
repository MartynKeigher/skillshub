import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct ProcessOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs a command and collects its output. Tests supply canned results instead of running
/// the user's real `claude`.
public protocol ProcessRunning: Sendable {
    /// With a `timeout`, the process is terminated when it runs longer and the call throws.
    func run(_ executable: URL, arguments: [String], environment: [String: String]?,
             currentDirectory: URL?, timeout: Duration?) async throws -> ProcessOutput
}

public extension ProcessRunning {
    func run(_ executable: URL, arguments: [String], environment: [String: String]? = nil,
             currentDirectory: URL? = nil) async throws -> ProcessOutput {
        try await run(executable, arguments: arguments, environment: environment,
                      currentDirectory: currentDirectory, timeout: nil)
    }
}

public struct ProcessTimeoutError: Error, Equatable {}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: URL, arguments: [String], environment: [String: String]?,
                    currentDirectory: URL?, timeout: Duration?) async throws -> ProcessOutput {
        try await Self.runOffMain(executable, arguments, environment, currentDirectory, timeout)
    }

    @concurrent private static func runOffMain(_ executable: URL, _ arguments: [String],
                                               _ environment: [String: String]?,
                                               _ currentDirectory: URL?,
                                               _ timeout: Duration?) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        // Read both pipes while the process runs; a full pipe would otherwise block it. The
        // reads end when every process holding the pipes has exited, children included.
        let collect = Task.detached { () -> ProcessOutput in
            async let stdout = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
            async let stderr = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
            let (outData, errData) = await (stdout, stderr)
            process.waitUntilExit()
            return ProcessOutput(exitCode: process.terminationStatus,
                                 stdout: String(decoding: outData, as: UTF8.self),
                                 stderr: String(decoding: errData, as: UTF8.self))
        }
        guard let timeout else { return await collect.value }

        // Whichever finishes first answers. A task group would wait for the read even after
        // the timeout, and the read only ends when the pipes close.
        let pid = process.processIdentifier
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            Task.detached {
                let output = await collect.value
                if once.claim() { continuation.resume(returning: output) }
            }
            Task.detached {
                try? await Task.sleep(for: timeout)
                guard once.claim() else { return }
                // A child that outlives its parent, such as `sleep` under `sh`, keeps the pipes
                // open, so the whole tree is ended, not just the process started here.
                terminateTree(pid)
                continuation.resume(throwing: ProcessTimeoutError())
            }
        }
    }

    private static func terminateTree(_ pid: Int32) {
        for child in childProcesses(of: pid) { terminateTree(child) }
        kill(pid, SIGTERM)
    }

    private static func childProcesses(of pid: Int32) -> [Int32] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", "\(pid)"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice
        guard (try? pgrep.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { Int32($0) }
    }
}

/// Lets exactly one of several racing tasks act.
private final class Once: @unchecked Sendable {
    private var claimed = false
    private let lock = NSLock()

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
