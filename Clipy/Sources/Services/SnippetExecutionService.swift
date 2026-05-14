//
//  SnippetExecutionService.swift
//
//  Clipy
//

import AppKit
import Foundation

struct SnippetExecutionRequest: Equatable {
    let content: String
    let type: CPYSnippet.SnippetType
    let scriptConfig: ScriptSnippetConfig

    init(content: String, type: CPYSnippet.SnippetType, scriptConfig: ScriptSnippetConfig) {
        self.content = content
        self.type = type
        self.scriptConfig = scriptConfig
    }

    init(snippet: CPYSnippet) {
        self.init(content: snippet.content, type: snippet.type, scriptConfig: snippet.scriptConfig)
    }
}

enum SnippetExecutionOutcome: Equatable {
    case pasted(String, isEphemeral: Bool)
    case copied(String, isEphemeral: Bool)
    case failed(String)
}

final class SnippetExecutionService {
    private static let maximumAutomaticPasteLatency: TimeInterval = 1.0

    typealias ScriptRunner = (String, ScriptSnippetConfig, @escaping (ScriptExecutionResult) -> Void) -> Void
    typealias Paste = (String, Bool) -> Void
    typealias Copy = (String, Bool) -> Void
    typealias ErrorPresenter = (String) -> Void
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void
    typealias CurrentPasteTarget = () -> pid_t?
    typealias CurrentDate = () -> Date

    static let shared = SnippetExecutionService(
        scriptRunner: { script, config, completion in
            ScriptExecutionService.execute(script: script, config: config, completion: completion)
        },
        paste: { text, isEphemeral in
            if isEphemeral {
                AppEnvironment.current.pasteService.pasteEphemeral(with: text)
            } else {
                AppEnvironment.current.pasteService.copyToPasteboard(with: text)
                AppEnvironment.current.pasteService.paste()
            }
        },
        presentError: { message in
            let alert = NSAlert()
            alert.messageText = "Script Snippet Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        },
        scheduler: { delay, action in
            guard delay > 0 else {
                action()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        },
        copy: { text, isEphemeral in
            if isEphemeral {
                AppEnvironment.current.pasteService.copyEphemeralToPasteboard(with: text)
            } else {
                AppEnvironment.current.pasteService.copyToPasteboard(with: text)
            }
        },
        currentPasteTarget: {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        currentDate: {
            Date()
        }
    )

    private let scriptRunner: ScriptRunner
    private let paste: Paste
    private let copy: Copy
    private let presentError: ErrorPresenter
    private let scheduler: Scheduler
    private let currentPasteTarget: CurrentPasteTarget
    private let currentDate: CurrentDate

    init(
        scriptRunner: @escaping ScriptRunner,
        paste: @escaping Paste,
        presentError: @escaping ErrorPresenter,
        scheduler: @escaping Scheduler,
        copy: @escaping Copy = { _, _ in },
        currentPasteTarget: @escaping CurrentPasteTarget = { nil },
        currentDate: @escaping CurrentDate = { Date() }
    ) {
        self.scriptRunner = scriptRunner
        self.paste = paste
        self.copy = copy
        self.presentError = presentError
        self.scheduler = scheduler
        self.currentPasteTarget = currentPasteTarget
        self.currentDate = currentDate
    }

    func execute(
        _ snippet: CPYSnippet,
        pasteDelay: TimeInterval = 0,
        completion: ((SnippetExecutionOutcome) -> Void)? = nil
    ) {
        execute(SnippetExecutionRequest(snippet: snippet), pasteDelay: pasteDelay, completion: completion)
    }

    func execute(
        _ request: SnippetExecutionRequest,
        pasteDelay: TimeInterval = 0,
        completion: ((SnippetExecutionOutcome) -> Void)? = nil
    ) {
        let expectedPasteTarget = currentPasteTarget()
        let startedAt = currentDate()

        switch request.type {
        case .plainText:
            let processed = SnippetVariableProcessor.process(request.content)
            schedulePaste(
                processed,
                isEphemeral: false,
                pasteDelay: pasteDelay,
                expectedPasteTarget: expectedPasteTarget,
                startedAt: startedAt,
                completion: completion
            )

        case .script:
            scriptRunner(request.content, request.scriptConfig) { [weak self] result in
                guard let self else { return }
                if let message = self.errorMessage(for: result, timeoutSeconds: request.scriptConfig.timeoutSeconds) {
                    self.presentError(message)
                    completion?(.failed(message))
                    return
                }

                self.schedulePaste(
                    result.output,
                    isEphemeral: request.scriptConfig.isEphemeral,
                    pasteDelay: pasteDelay,
                    expectedPasteTarget: expectedPasteTarget,
                    startedAt: startedAt,
                    completion: completion
                )
            }
        }
    }

    func testRun(
        _ request: SnippetExecutionRequest,
        completion: @escaping (ScriptExecutionResult) -> Void
    ) {
        switch request.type {
        case .plainText:
            let processed = SnippetVariableProcessor.process(request.content)
            completion(ScriptExecutionResult(output: processed, stderr: "", exitCode: 0, timedOut: false))

        case .script:
            scriptRunner(request.content, request.scriptConfig, completion)
        }
    }

    private func schedulePaste(
        _ text: String,
        isEphemeral: Bool,
        pasteDelay: TimeInterval,
        expectedPasteTarget: pid_t?,
        startedAt: Date,
        completion: ((SnippetExecutionOutcome) -> Void)?
    ) {
        scheduler(pasteDelay) { [copy, currentDate, currentPasteTarget, paste] in
            let elapsed = currentDate().timeIntervalSince(startedAt)
            let pasteTargetChanged = expectedPasteTarget.map { currentPasteTarget() != $0 } ?? false
            if pasteTargetChanged || elapsed > Self.maximumAutomaticPasteLatency {
                copy(text, isEphemeral)
                completion?(.copied(text, isEphemeral: isEphemeral))
                return
            }
            paste(text, isEphemeral)
            completion?(.pasted(text, isEphemeral: isEphemeral))
        }
    }

    private func errorMessage(for result: ScriptExecutionResult, timeoutSeconds: Int) -> String? {
        if result.timedOut {
            return "Script timed out after \(timeoutSeconds)s."
        }
        if let launchError = result.launchError {
            return "Script could not be launched: \(launchError)"
        }
        if result.outputTruncated {
            return "Script output exceeded \(ScriptExecutionService.maxOutputSize) bytes and was not pasted."
        }
        if result.stderrTruncated {
            return "Script error output exceeded \(ScriptExecutionService.maxOutputSize) bytes."
        }
        if result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = stderr.isEmpty ? "No error output." : stderr
            return "Script failed with exit \(result.exitCode): \(detail)"
        }
        return nil
    }
}
