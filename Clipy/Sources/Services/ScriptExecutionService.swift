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

    init(output: String, stderr: String, exitCode: Int32, timedOut: Bool, launchError: String? = nil) {
        self.output = output
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.launchError = launchError
    }
}

struct ScriptExecutionService {
    static let maxOutputSize = 1_048_576
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.shell)
        process.arguments = ["-c", script]
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        process.environment = environment(clipboard: clipboard)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutReader = NonBlockingPipeReader(handle: stdoutPipe.fileHandleForReading, limit: maxOutputSize)
        let stderrReader = NonBlockingPipeReader(handle: stderrPipe.fileHandleForReading, limit: maxOutputSize)

        do {
            try process.run()
            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
        } catch {
            scriptLogger.error("Failed to launch script: \(error.localizedDescription)")
            return ScriptExecutionResult(output: "", stderr: "", exitCode: -1, timedOut: false, launchError: error.localizedDescription)
        }

        var timedOut = false
        var killDeadline: Date?
        let timeoutDeadline = Date().addingTimeInterval(config.timeout)
        let readers = [stdoutReader, stderrReader]

        while process.isRunning {
            readers.forEach { $0.drainAvailable() }

            let now = Date()
            if now >= timeoutDeadline && !timedOut {
                timedOut = true
                process.terminate()
                killDeadline = now.addingTimeInterval(terminationGracePeriod)
            }

            if let killDeadline, now >= killDeadline, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }

            waitForPipeData(readers, timeoutMilliseconds: 25)
        }

        process.waitUntilExit()
        readers.forEach { $0.drainAvailable() }

        let output = String(data: stdoutReader.data, encoding: .utf8) ?? ""
        let stderr = String(data: stderrReader.data, encoding: .utf8) ?? ""

        return ScriptExecutionResult(
            output: output,
            stderr: stderr,
            exitCode: process.terminationStatus,
            timedOut: timedOut
        )
    }

    private static func environment(clipboard: String?) -> [String: String] {
        // Script snippets receive a minimal documented environment by default.
        var environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        if let clipboard {
            environment["CLIPBOARD"] = clipboard
        }
        return environment
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
