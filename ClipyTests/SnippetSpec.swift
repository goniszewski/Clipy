import Quick
import Nimble
import RealmSwift
@testable import Clipy

class SnippetSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        describeSyncDatabase()
        describeScriptSnippetMetadata()
        describeSnippetExecutionService()
        describeScriptExecutionService()
        describeEphemeralPasteBehavior()
    }
}

private extension SnippetSpec {
    class func describeSyncDatabase() {
        describe("Sync database") {

            it("Merge snippet") {
                let snippet = CPYSnippet()
                let realm = try! Realm()
                realm.transaction { realm.add(snippet) }

                let snippet2 = CPYSnippet()
                snippet2.identifier = snippet.identifier
                snippet2.index = 100
                snippet2.title = "title"
                snippet2.content = "content"
                snippet2.merge()
                expect(snippet2.realm).to(beNil())

                expect(snippet.index) == snippet2.index
                expect(snippet.title) == snippet2.title
                expect(snippet.content) == snippet2.content
            }

            it("Remove snippet") {
                let realm = try! Realm()
                expect(realm.objects(CPYSnippet.self).count) == 0

                let snippet = CPYSnippet()
                realm.transaction { realm.add(snippet) }

                expect(realm.objects(CPYSnippet.self).count) == 1

                let snippet2 = CPYSnippet()
                snippet2.identifier = snippet.identifier
                snippet2.remove()

                expect(realm.objects(CPYSnippet.self).count) == 0
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }
        }
    }
}

private extension SnippetSpec {
    class func describeScriptSnippetMetadata() {
        describe("Script snippet metadata") {

            it("defaults new snippets to plain text with bounded explicit script settings") {
                let snippet = CPYSnippet()

                expect(snippet.type) == CPYSnippet.SnippetType.plainText
                expect(snippet.snippetType) == CPYSnippet.SnippetType.plainText.rawValue
                expect(snippet.scriptShell) == CPYSnippet.defaultScriptShell
                expect(snippet.scriptTimeout) == CPYSnippet.defaultScriptTimeout
                expect(snippet.isEphemeral).to(beTrue())
                expect(snippet.scriptConfig) == ScriptSnippetConfig(
                    shell: CPYSnippet.defaultScriptShell,
                    timeoutSeconds: CPYSnippet.defaultScriptTimeout,
                    isEphemeral: true
                )
            }

            it("normalizes script configs before execution uses them") {
                let config = ScriptSnippetConfig(shell: "  ", timeoutSeconds: 0, isEphemeral: false)

                expect(config.shell) == CPYSnippet.defaultScriptShell
                expect(config.timeoutSeconds) == CPYSnippet.defaultScriptTimeout
                expect(config.isEphemeral).to(beFalse())
            }
        }
    }
}

private extension SnippetSpec {
    class func describeSnippetExecutionService() {
        describe("Snippet execution service") {

            it("pastes plain text snippets through the shared path") {
                let snippet = CPYSnippet()
                snippet.content = "plain snippet"

                var scriptWasRun = false
                var pasted: [(String, Bool)] = []
                var errors = [String]()
                let service = SnippetExecutionService(
                    scriptRunner: { _, _, _ in scriptWasRun = true },
                    paste: { pasted.append(($0, $1)) },
                    presentError: { errors.append($0) },
                    scheduler: { _, action in action() }
                )

                var outcome: SnippetExecutionOutcome?
                service.execute(snippet) { outcome = $0 }

                expect(scriptWasRun).to(beFalse())
                expect(pasted.count) == 1
                expect(pasted.first?.0) == "plain snippet"
                expect(pasted.first?.1).to(beFalse())
                expect(errors).to(beEmpty())
                expect(outcome) == .pasted("plain snippet", isEphemeral: false)
            }

            it("runs script snippets through the shared runner and honors ephemeral output") {
                let snippet = CPYSnippet()
                snippet.type = .script
                snippet.content = "printf script-output"
                snippet.scriptShell = "/bin/zsh"
                snippet.scriptTimeout = 5
                snippet.isEphemeral = true

                var receivedScript: String?
                var receivedConfig: ScriptSnippetConfig?
                var pasted: [(String, Bool)] = []
                let service = SnippetExecutionService(
                    scriptRunner: { script, config, completion in
                        receivedScript = script
                        receivedConfig = config
                        completion(ScriptExecutionResult(output: "script-output", stderr: "", exitCode: 0, timedOut: false))
                    },
                    paste: { pasted.append(($0, $1)) },
                    presentError: { _ in },
                    scheduler: { _, action in action() }
                )

                var outcome: SnippetExecutionOutcome?
                service.execute(snippet) { outcome = $0 }

                expect(receivedScript) == "printf script-output"
                expect(receivedConfig) == ScriptSnippetConfig(shell: "/bin/zsh", timeoutSeconds: 5, isEphemeral: true)
                expect(pasted.count) == 1
                expect(pasted.first?.0) == "script-output"
                expect(pasted.first?.1).to(beTrue())
                expect(outcome) == .pasted("script-output", isEphemeral: true)
            }

            it("reports script failures without pasting output") {
                let snippet = CPYSnippet()
                snippet.type = .script
                snippet.content = "exit 2"

                var pasted: [(String, Bool)] = []
                var errors = [String]()
                let service = SnippetExecutionService(
                    scriptRunner: { _, _, completion in
                        completion(ScriptExecutionResult(output: "", stderr: "bad script", exitCode: 2, timedOut: false))
                    },
                    paste: { pasted.append(($0, $1)) },
                    presentError: { errors.append($0) },
                    scheduler: { _, action in action() }
                )

                var outcome: SnippetExecutionOutcome?
                service.execute(snippet) { outcome = $0 }

                expect(pasted).to(beEmpty())
                expect(errors.count) == 1
                expect(errors.first).to(contain("exit 2"))
                expect(errors.first).to(contain("bad script"))
                expect(outcome) == .failed(errors.first ?? "")
            }

            it("copies script output instead of pasting when the paste target changes") {
                let snippet = CPYSnippet()
                snippet.type = .script
                snippet.content = "printf delayed"

                var target: pid_t? = 100
                var pasted: [(String, Bool)] = []
                var copied: [(String, Bool)] = []
                let service = SnippetExecutionService(
                    scriptRunner: { _, _, completion in
                        target = 200
                        completion(ScriptExecutionResult(output: "delayed", stderr: "", exitCode: 0, timedOut: false))
                    },
                    paste: { pasted.append(($0, $1)) },
                    presentError: { _ in },
                    scheduler: { _, action in action() },
                    copy: { copied.append(($0, $1)) },
                    currentPasteTarget: { target }
                )

                var outcome: SnippetExecutionOutcome?
                service.execute(snippet) { outcome = $0 }

                expect(pasted).to(beEmpty())
                expect(copied.count) == 1
                expect(copied.first?.0) == "delayed"
                expect(outcome) == .copied("delayed", isEphemeral: true)
            }

            it("copies delayed script output even when the same application remains focused") {
                let snippet = CPYSnippet()
                snippet.type = .script
                snippet.content = "printf delayed"

                var now = Date()
                var pasted: [(String, Bool)] = []
                var copied: [(String, Bool)] = []
                let service = SnippetExecutionService(
                    scriptRunner: { _, _, completion in
                        now = now.addingTimeInterval(2)
                        completion(ScriptExecutionResult(output: "delayed", stderr: "", exitCode: 0, timedOut: false))
                    },
                    paste: { pasted.append(($0, $1)) },
                    presentError: { _ in },
                    scheduler: { _, action in action() },
                    copy: { copied.append(($0, $1)) },
                    currentPasteTarget: { 100 },
                    currentDate: { now }
                )

                var outcome: SnippetExecutionOutcome?
                service.execute(snippet) { outcome = $0 }

                expect(pasted).to(beEmpty())
                expect(copied.count) == 1
                expect(copied.first?.0) == "delayed"
                expect(outcome) == .copied("delayed", isEphemeral: true)
            }

            it("runs script tests through the shared runner without pasting or presenting alerts") {
                let request = SnippetExecutionRequest(
                    content: "printf test",
                    type: .script,
                    scriptConfig: ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 4, isEphemeral: true)
                )
                var receivedScript: String?
                var receivedConfig: ScriptSnippetConfig?
                var pasted: [(String, Bool)] = []
                var errors = [String]()
                let service = SnippetExecutionService(
                    scriptRunner: { script, config, completion in
                        receivedScript = script
                        receivedConfig = config
                        completion(ScriptExecutionResult(output: "test", stderr: "note", exitCode: 0, timedOut: false))
                    },
                    paste: { pasted.append(($0, $1)) },
                    presentError: { errors.append($0) },
                    scheduler: { _, action in action() }
                )

                var result: ScriptExecutionResult?
                service.testRun(request) { result = $0 }

                expect(receivedScript) == "printf test"
                expect(receivedConfig) == ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 4, isEphemeral: true)
                expect(result) == ScriptExecutionResult(output: "test", stderr: "note", exitCode: 0, timedOut: false)
                expect(pasted).to(beEmpty())
                expect(errors).to(beEmpty())
            }
        }
    }
}

private extension SnippetSpec {
    class func describeScriptExecutionService() {
        describe("Script execution service") {

            it("captures stdout exactly up to the output cap") {
                waitUntil(timeout: .seconds(3)) { done in
                    ScriptExecutionService.execute(
                        script: "printf 'value\\n'",
                        config: ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 2, isEphemeral: true)
                    ) { result in
                        expect(result.output) == "value\n"
                        expect(result.stderr).to(beEmpty())
                        expect(result.exitCode) == 0
                        expect(result.timedOut).to(beFalse())
                        done()
                    }
                }
            }

            it("reports non-zero exits without requiring stderr output") {
                waitUntil(timeout: .seconds(3)) { done in
                    ScriptExecutionService.execute(
                        script: "exit 7",
                        config: ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 2, isEphemeral: true)
                    ) { result in
                        expect(result.output).to(beEmpty())
                        expect(result.stderr).to(beEmpty())
                        expect(result.exitCode) == 7
                        expect(result.timedOut).to(beFalse())
                        done()
                    }
                }
            }

            it("finishes timed-out scripts that ignore SIGTERM") {
                waitUntil(timeout: .seconds(4)) { done in
                    ScriptExecutionService.execute(
                        script: "trap '' TERM; while :; do sleep 0.1; done",
                        config: ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 1, isEphemeral: true)
                    ) { result in
                        expect(result.timedOut).to(beTrue())
                        expect(result.exitCode).toNot(equal(0))
                        done()
                    }
                }
            }

            it("drains large output while capping captured stdout") {
                let script = "i=0; while [ $i -lt 9000 ]; do printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'; i=$((i + 1)); done"

                waitUntil(timeout: .seconds(5)) { done in
                    ScriptExecutionService.execute(
                        script: script,
                        config: ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 3, isEphemeral: true)
                    ) { result in
                        expect(result.output.count) == ScriptExecutionService.maxOutputSize
                        expect(result.stderr).to(beEmpty())
                        expect(result.exitCode) == 0
                        expect(result.timedOut).to(beFalse())
                        expect(result.outputTruncated).to(beTrue())
                        done()
                    }
                }
            }

            it("decodes invalid UTF-8 output lossily instead of dropping all captured bytes") {
                waitUntil(timeout: .seconds(3)) { done in
                    ScriptExecutionService.execute(
                        script: "printf '\\303('",
                        config: ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 2, isEphemeral: true)
                    ) { result in
                        expect(result.output).to(contain("("))
                        expect(result.output.unicodeScalars.contains { $0.value == 0xfffd }).to(beTrue())
                        expect(result.exitCode) == 0
                        done()
                    }
                }
            }

            it("rejects successful script output that exceeds the capture limit before pasting") {
                let snippet = CPYSnippet()
                snippet.type = .script
                snippet.content = "large output"

                var pasted: [(String, Bool)] = []
                var errors = [String]()
                let service = SnippetExecutionService(
                    scriptRunner: { _, _, completion in
                        completion(ScriptExecutionResult(
                            output: "partial",
                            stderr: "",
                            exitCode: 0,
                            timedOut: false,
                            outputTruncated: true
                        ))
                    },
                    paste: { pasted.append(($0, $1)) },
                    presentError: { errors.append($0) },
                    scheduler: { _, action in action() }
                )

                var outcome: SnippetExecutionOutcome?
                service.execute(snippet) { outcome = $0 }

                expect(pasted).to(beEmpty())
                expect(errors.first).to(contain("output exceeded"))
                expect(outcome) == .failed(errors.first ?? "")
            }

            it("omits oversized clipboard text from scripts that do not request it") {
                let environment = ScriptExecutionService.environment(
                    script: "printf ok",
                    clipboard: String(repeating: "x", count: ScriptExecutionService.maxClipboardEnvironmentBytes + 1)
                )

                expect(environment["CLIPBOARD"]).to(beNil())
            }

            it("fails before launch when an oversized clipboard is requested") {
                let environmentError = ScriptExecutionService.environmentError(
                    script: "printf %s \"$CLIPBOARD\"",
                    clipboard: String(repeating: "x", count: ScriptExecutionService.maxClipboardEnvironmentBytes + 1)
                )

                expect(environmentError).to(contain("too large"))
            }

            it("handles successful scripts with empty output") {
                waitUntil(timeout: .seconds(3)) { done in
                    ScriptExecutionService.execute(
                        script: ":",
                        config: ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 2, isEphemeral: true)
                    ) { result in
                        expect(result.output).to(beEmpty())
                        expect(result.stderr).to(beEmpty())
                        expect(result.exitCode) == 0
                        expect(result.timedOut).to(beFalse())
                        done()
                    }
                }
            }

            it("returns when a background child keeps inherited output pipes open") {
                waitUntil(timeout: .seconds(3)) { done in
                    ScriptExecutionService.execute(
                        script: "sleep 5 &",
                        config: ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 2, isEphemeral: true)
                    ) { result in
                        expect(result.output).to(beEmpty())
                        expect(result.stderr).to(beEmpty())
                        expect(result.exitCode) == 0
                        expect(result.timedOut).to(beFalse())
                        done()
                    }
                }
            }

            it("kills child processes in the script process group after a timeout") {
                let markerURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("clipy-script-child-\(UUID().uuidString)")
                let script = "trap '' TERM; (trap '' TERM; while :; do sleep 0.1; done) & echo $! > '\(markerURL.path)'; wait"

                waitUntil(timeout: .seconds(5)) { done in
                    ScriptExecutionService.execute(
                        script: script,
                        config: ScriptSnippetConfig(shell: "/bin/sh", timeoutSeconds: 1, isEphemeral: true)
                    ) { result in
                        expect(result.timedOut).to(beTrue())

                        let pid = String(data: (try? Data(contentsOf: markerURL)) ?? Data(), encoding: .utf8)
                            .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        if let pid {
                            var isRunning = Darwin.kill(pid, 0) == 0
                            let deadline = Date().addingTimeInterval(0.8)
                            while isRunning && Date() < deadline {
                                Thread.sleep(forTimeInterval: 0.05)
                                isRunning = Darwin.kill(pid, 0) == 0
                            }
                            expect(isRunning).to(beFalse())
                            _ = Darwin.kill(pid, SIGKILL)
                        }
                        try? FileManager.default.removeItem(at: markerURL)
                        done()
                    }
                }
            }
        }
    }
}

private extension SnippetSpec {
    class func describeEphemeralPasteBehavior() {
        describe("Ephemeral paste behavior") {

            it("consumes only the registered pasteboard change count") {
                let service = ClipService()

                service.skipCapture(forChangeCount: 12)

                expect(service.shouldSkipCapture(forChangeCount: 11)).to(beFalse())
                expect(service.shouldSkipCapture(forChangeCount: 12)).to(beTrue())
                expect(service.shouldSkipCapture(forChangeCount: 12)).to(beFalse())
            }

            it("prunes stale skip tokens when a newer pasteboard change is observed") {
                let service = ClipService()

                service.skipCapture(forChangeCount: 12)

                expect(service.shouldSkipCapture(forChangeCount: 13)).to(beFalse())
                expect(service.shouldSkipCapture(forChangeCount: 12)).to(beFalse())
            }

            it("registers the exact pasteboard change written by an ephemeral paste") {
                var copiedStrings = [String]()
                var skippedChangeCounts = [Int]()
                var didPaste = false

                let coordinator = EphemeralPasteCoordinator(
                    copyString: { string in
                        copiedStrings.append(string)
                        return 42
                    },
                    currentChangeCount: { 42 },
                    clearContents: { 43 },
                    registerSkip: { skippedChangeCounts.append($0) },
                    paste: { didPaste = true },
                    scheduler: { _, _ in }
                )

                coordinator.paste("secret", autoClearDelay: 0)

                expect(copiedStrings) == ["secret"]
                expect(skippedChangeCounts) == [42]
                expect(didPaste).to(beTrue())
            }

            it("auto-clears ephemeral content only while the pasteboard is unchanged") {
                var currentChangeCount = 42
                var clearCount = 0
                var skippedChangeCounts = [Int]()
                var scheduledDelay: TimeInterval?
                var scheduledAction: (() -> Void)?

                let coordinator = EphemeralPasteCoordinator(
                    copyString: { _ in 42 },
                    currentChangeCount: { currentChangeCount },
                    clearContents: {
                        clearCount += 1
                        currentChangeCount = 43
                        return currentChangeCount
                    },
                    registerSkip: { skippedChangeCounts.append($0) },
                    paste: {},
                    scheduler: { delay, action in
                        scheduledDelay = delay
                        scheduledAction = action
                    }
                )

                coordinator.paste("secret", autoClearDelay: 15)
                scheduledAction?()

                expect(scheduledDelay) == 15
                expect(clearCount) == 1
                expect(skippedChangeCounts) == [42, 43]

                currentChangeCount = 42
                clearCount = 0
                skippedChangeCounts.removeAll()
                scheduledAction = nil

                coordinator.paste("secret", autoClearDelay: 15)
                currentChangeCount = 99
                scheduledAction?()

                expect(clearCount) == 0
                expect(skippedChangeCounts) == [42]
            }
        }
    }
}
