import Quick
import Nimble
import RealmSwift
@testable import Clipy

class SnippetSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

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
        }

        describeEphemeralPasteBehavior()

        describeScriptExecutionService()

    }

    private class func describeScriptExecutionService() {
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
                        done()
                    }
                }
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
        }
    }

    private class func describeEphemeralPasteBehavior() {
        describe("Ephemeral paste behavior") {

            it("consumes only the registered pasteboard change count") {
                let service = ClipService()

                service.skipCapture(forChangeCount: 12)

                expect(service.shouldSkipCapture(forChangeCount: 11)).to(beFalse())
                expect(service.shouldSkipCapture(forChangeCount: 12)).to(beTrue())
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
