//
//  ScriptExecutionService.swift
//
//  Clipy
//

import Cocoa
import Darwin
import Foundation
import os.log

private let scriptLogger = Logger(subsystem: "com.clipy-app.Clipy", category: "ScriptExecution")

struct ScriptSnippetConfig: Hashable {
    static let minimumTimeoutSeconds = 1
    static let maximumTimeoutSeconds = 60

    let shell: String
    let timeoutSeconds: Int
    let isEphemeral: Bool

    init(shell: String, timeoutSeconds: Int, isEphemeral: Bool) {
        let trimmedShell = shell.trimmingCharacters(in: .whitespacesAndNewlines)
        self.shell = trimmedShell.isEmpty ? CPYSnippet.defaultScriptShell : trimmedShell
        if (Self.minimumTimeoutSeconds...Self.maximumTimeoutSeconds).contains(timeoutSeconds) {
            self.timeoutSeconds = timeoutSeconds
        } else {
            self.timeoutSeconds = CPYSnippet.defaultScriptTimeout
        }
        self.isEphemeral = isEphemeral
    }

    var timeout: TimeInterval {
        TimeInterval(timeoutSeconds)
    }
}

struct ScriptExecutionResult: Equatable {
    let output: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool
    let launchError: String?
    let outputTruncated: Bool
    let stderrTruncated: Bool

    init(
        output: String,
        stderr: String,
        exitCode: Int32,
        timedOut: Bool,
        launchError: String? = nil,
        outputTruncated: Bool = false,
        stderrTruncated: Bool = false
    ) {
        self.output = output
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.launchError = launchError
        self.outputTruncated = outputTruncated
        self.stderrTruncated = stderrTruncated
    }
}

struct ScriptExecutionService {
    static let maxOutputSize = 1_048_576
    static let maxClipboardEnvironmentBytes = 64 * 1024
    private static let terminationGracePeriod: TimeInterval = 0.5

    static func execute(
        script: String,
        config: ScriptSnippetConfig,
        completion: @escaping (ScriptExecutionResult) -> Void
    ) {
        let clipboard = NSPasteboard.general.string(forType: .string)

        DispatchQueue.global(qos: .userInitiated).async {
            let result = run(script: script, config: config, clipboard: clipboard)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func run(script: String, config: ScriptSnippetConfig, clipboard: String?) -> ScriptExecutionResult {
        if let environmentError = environmentError(script: script, clipboard: clipboard) {
            return ScriptExecutionResult(output: "", stderr: "", exitCode: -1, timedOut: false, launchError: environmentError)
        }

        let subprocess = ScriptSubprocess(
            shell: config.shell,
            script: script,
            currentDirectory: NSTemporaryDirectory(),
            environment: environment(script: script, clipboard: clipboard)
        )

        let stdoutReader = NonBlockingPipeReader(handle: subprocess.stdoutReadHandle, limit: maxOutputSize)
        let stderrReader = NonBlockingPipeReader(handle: subprocess.stderrReadHandle, limit: maxOutputSize)

        do {
            try subprocess.run()
            subprocess.closeWriteHandles()
        } catch {
            scriptLogger.error("Failed to launch script: \(error.localizedDescription)")
            return ScriptExecutionResult(output: "", stderr: "", exitCode: -1, timedOut: false, launchError: error.localizedDescription)
        }

        var timedOut = false
        var killDeadline: Date?
        let timeoutDeadline = Date().addingTimeInterval(config.timeout)
        let readers = [stdoutReader, stderrReader]

        while true {
            readers.forEach { $0.drainAvailable() }

            let now = Date()
            if !timedOut {
                if subprocess.hasExited {
                    break
                }
                if now >= timeoutDeadline {
                    timedOut = true
                    subprocess.signalProcessGroup(SIGTERM)
                    killDeadline = now.addingTimeInterval(terminationGracePeriod)
                }
            } else if let killDeadline, now >= killDeadline {
                // Keep the shell unreaped until after the final group signal so its pid
                // cannot be reused as a different process group before SIGKILL.
                subprocess.signalProcessGroup(SIGKILL)
                break
            }

            waitForPipeData(readers, timeoutMilliseconds: 25)
        }

        let exitCode = subprocess.waitUntilExit()
        readers.forEach { $0.drainAvailable() }

        let output = String(decoding: stdoutReader.data, as: UTF8.self)
        let stderr = String(decoding: stderrReader.data, as: UTF8.self)

        return ScriptExecutionResult(
            output: output,
            stderr: stderr,
            exitCode: exitCode,
            timedOut: timedOut,
            outputTruncated: stdoutReader.isTruncated,
            stderrTruncated: stderrReader.isTruncated
        )
    }

    static func environment(script: String, clipboard: String?) -> [String: String] {
        // Script snippets receive a minimal documented environment by default.
        var environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        if let clipboard, scriptRequestsClipboard(script), environmentError(script: script, clipboard: clipboard) == nil {
            environment["CLIPBOARD"] = clipboard
        }
        return environment
    }

    static func environmentError(script: String, clipboard: String?) -> String? {
        guard let clipboard, scriptRequestsClipboard(script) else { return nil }
        guard clipboard.utf8.count > maxClipboardEnvironmentBytes else { return nil }
        return "Current clipboard text is too large to expose as CLIPBOARD."
    }

    private static func scriptRequestsClipboard(_ script: String) -> Bool {
        script.contains("CLIPBOARD")
    }

    private static func waitForPipeData(_ readers: [NonBlockingPipeReader], timeoutMilliseconds: Int32) {
        var descriptors = readers.map {
            pollfd(fd: $0.fileDescriptor, events: Int16(POLLIN), revents: 0)
        }
        _ = poll(&descriptors, nfds_t(descriptors.count), timeoutMilliseconds)
    }
}

private final class NonBlockingPipeReader {
    private let limit: Int
    private var collected = Data()
    private var stored = 0
    private(set) var isTruncated = false

    let fileDescriptor: Int32

    init(handle: FileHandle, limit: Int) {
        self.fileDescriptor = handle.fileDescriptor
        self.limit = limit

        let flags = fcntl(fileDescriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        }
    }

    var data: Data {
        collected
    }

    func drainAvailable() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
            }

            if bytesRead > 0 {
                if stored < limit {
                    let appendCount = min(Int(bytesRead), limit - stored)
                    collected.append(contentsOf: buffer.prefix(appendCount))
                    stored += appendCount
                    if appendCount < bytesRead {
                        isTruncated = true
                    }
                } else {
                    isTruncated = true
                }
                continue
            }

            if bytesRead == -1 && errno == EINTR {
                continue
            }
            break
        }
    }
}

private final class ScriptSubprocess {
    let stdoutReadHandle: FileHandle
    let stderrReadHandle: FileHandle

    private let shell: String
    private let script: String
    private let currentDirectory: String
    private let environment: [String: String]
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var pid: pid_t = 0
    private var waitStatus: Int32?

    init(shell: String, script: String, currentDirectory: String, environment: [String: String]) {
        self.shell = shell
        self.script = script
        self.currentDirectory = currentDirectory
        self.environment = environment
        self.stdoutReadHandle = stdoutPipe.fileHandleForReading
        self.stderrReadHandle = stderrPipe.fileHandleForReading
    }

    func run() throws {
        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }

        try check(posix_spawn_file_actions_adddup2(&actions, stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO))
        try currentDirectory.withCString { path in
            try check(posix_spawn_file_actions_addchdir_np(&actions, path))
        }

        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }

        let flags = Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT)
        try check(posix_spawnattr_setflags(&attributes, flags))

        let arguments = [shell, "-c", script]
        let environmentPairs = environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()

        try withCStringArray(arguments) { argv in
            try withCStringArray(environmentPairs) { envp in
                let result = shell.withCString { shellPath in
                    posix_spawn(&pid, shellPath, &actions, &attributes, argv, envp)
                }
                try check(result)
            }
        }
    }

    func closeWriteHandles() {
        stdoutPipe.fileHandleForWriting.closeFile()
        stderrPipe.fileHandleForWriting.closeFile()
    }

    var hasExited: Bool {
        if waitStatus != nil { return true }

        while true {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                waitStatus = status
                return true
            }
            if result == 0 {
                return false
            }
            if result == -1 && errno == EINTR {
                continue
            }
            return false
        }
    }

    func signalProcessGroup(_ signal: Int32) {
        guard pid > 0 else { return }
        _ = kill(-pid, signal)
    }

    func waitUntilExit() -> Int32 {
        if let waitStatus {
            return Self.terminationStatus(from: waitStatus)
        }

        while true {
            var status: Int32 = 0
            let result = waitpid(pid, &status, 0)
            if result == pid {
                waitStatus = status
                return Self.terminationStatus(from: status)
            }
            if result == -1 && errno == EINTR {
                continue
            }
            return -1
        }
    }

    private func check(_ result: Int32) throws {
        guard result == 0 else { throw SpawnError(code: result) }
    }

    private func withCStringArray<Result>(
        _ strings: [String],
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
    ) throws -> Result {
        let cStrings = try strings.map { string -> UnsafeMutablePointer<CChar> in
            guard let cString = strdup(string) else { throw SpawnError(code: ENOMEM) }
            return cString
        }
        defer { cStrings.forEach { free($0) } }

        var pointers = cStrings.map { Optional($0) }
        pointers.append(nil)
        return try pointers.withUnsafeMutableBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }

    private static func terminationStatus(from status: Int32) -> Int32 {
        let statusCode = status & 0x7f
        if statusCode == 0 {
            return (status >> 8) & 0xff
        }
        if statusCode != 0x7f {
            return statusCode
        }
        return status
    }
}

private struct SpawnError: LocalizedError {
    let code: Int32

    var errorDescription: String? {
        String(cString: strerror(code))
    }
}
