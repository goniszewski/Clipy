# PR #3 Import Todo

This document tracks which ideas from PR #3 should be imported into Clipy Classic after refactor, which items are already covered, and which items should not be imported.

Source PR: https://github.com/goniszewski/Clipy/pull/3

## Decision Summary

- Do not merge PR #3 as-is.
- Import useful features as focused branches on top of current `develop`.
- Preserve Clipy Classic branding, v26 calendar versioning, Sparkle/manual update flow, archive compatibility, and the current snippets editor improvements.
- Treat script execution, ephemeral paste, and plugins as security-sensitive work requiring design cleanup and verification before shipping.

## Import Plan

### Phase 1: Small Menu Fixes

- [x] Re-check whether the history submenu folder fix is still needed in current `MenuManager.swift`.
- [x] If needed, import the history folder behavior so layout preferences are honored:
  - [x] `numberOfItemsPlaceInline`
  - [x] `numberOfItemsPlaceInsideFolder`
  - [x] `maxHistorySize`
- [x] Verify submenu index handling against the current menu structure.
- [x] Preserve current keyboard navigation for parent history ranges.
- [x] Verify pinned clips still sort first and remain visible.
- [x] Verify pinned image/PDF/file clips keep the pin indicator.
- [x] Verify the 10th visible menu item displays as `10.` while the shortcut remains `0`.
- [x] Add or update focused tests where feasible.
- [x] Build the app after changes.

### Phase 2: Script Snippets Core

- [x] Add script snippet data model fields on top of the current Realm schema:
  - [x] `snippetType`
  - [x] `scriptShell`
  - [x] `scriptTimeout`
  - [x] `isEphemeral`
- [x] Bump Realm schema from the current fork version, not from PR #3 blindly.
- [x] Add migration defaults for existing snippets:
  - [x] Existing snippets become plain text snippets.
  - [x] Default shell is conservative and explicit.
  - [x] Default timeout is bounded.
  - [x] Script output is ephemeral by default.
- [x] Replace loose script-related fields with a small script config type where it reduces call-site mistakes.
- [x] Add a shared snippet execution path, likely `SnippetExecutionService`.
- [x] Route script execution through the shared path from:
  - [x] Classic menu snippet selection.
  - [x] Modern snippet picker.
  - [x] Snippet editor test run.
- [x] Avoid duplicating timeout/error/paste behavior between `AppDelegate` and snippet picker view models.
- [x] Add script snippet icons/badges in menu and picker.
- [x] Preserve existing plain text snippet variable expansion.
- [ ] Build and manually verify plain snippets still paste exactly as before.

### Phase 3: Safe Script Execution

- [x] Introduce a script execution service based on the PR idea.
- [x] Keep pipe draining so scripts cannot deadlock when stdout/stderr are large.
- [x] Keep a hard output size cap.
- [x] Treat non-zero exit codes as errors even when stderr is empty.
- [x] Show useful script error messages to users.
- [x] Fix timeout escalation so delayed `SIGKILL` cannot target a reused PID.
- [x] Cancel or guard timeout escalation once the process exits.
- [x] Decide whether script processes inherit the full app environment.
- [x] Prefer a minimal, explicit environment where possible.
- [x] Provide documented environment variables:
  - [x] `CLIPBOARD`, only when intended.
  - [x] `HOME`, if needed.
  - [x] `PATH`, if needed.
- [x] Add focused tests for:
  - [x] Successful stdout capture.
  - [x] Non-zero exit handling.
  - [x] Timeout handling.
  - [x] Large output draining.
  - [x] Empty output.

### Phase 4: Ephemeral Paste

- [x] Implement ephemeral paste as a first-class behavior.
- [x] Fix PR #3's change-count bug:
  - [ ] Either record `NSPasteboard.general.changeCount + 1` before writing.
  - [x] Or register the skip token immediately after the pasteboard write.
- [x] Ensure script output marked ephemeral is not saved to clipboard history.
- [x] Ensure auto-clear only clears the pasteboard if the pasteboard has not changed since the ephemeral write.
- [x] Add user preference for auto-clear delay:
  - [x] Off
  - [x] 15 seconds
  - [x] 30 seconds
  - [x] 60 seconds
- [x] Pick a default delay deliberately.
- [x] Avoid wiping user clipboard content copied after the script output.
- [ ] Verify ephemeral paste still works if automatic paste is disabled and the user pastes manually.
- [x] Add tests or instrumentation around skip-token behavior.

### Phase 5: Editor UI For Script Snippets

- [x] Add a text/script segmented control or equivalent UI in the current snippets editor.
- [x] Add shell selector.
- [x] Add timeout picker/input.
- [x] Add `Ephemeral output` toggle.
- [x] Add `Test Run` button.
- [x] Show test output, stderr, exit code, and timeout state clearly.
- [x] Reset all script editing state when no snippet is selected.
- [x] Ensure state does not leak between selected snippets.
- [x] Preserve current drag reorder, insertion indicators, vault behavior, and close button.
- [x] Keep current editor layout and visual style.
- [x] Ensure XML import/export preserves script fields.
- [x] Put new XML element names in `Constants.Xml`.
- [x] Extract shared XML read/write helpers for script fields to avoid duplicate modern/legacy code.

### Phase 6: Template Gallery

- [x] Import the template gallery concept only after script snippets are stable.
- [x] Keep generic templates that are broadly useful:
  - [x] JSON pretty print.
  - [x] JSON minify.
  - [x] Base64 encode.
  - [x] Base64 decode.
  - [x] URL encode.
  - [x] JWT payload decode.
  - [x] Epoch to date.
  - [x] Markdown to HTML omitted for now because there is no acceptable bundled Markdown dependency.
  - [x] UUID generation.
  - [x] Password generation, after reviewing pipeline behavior.
- [x] Do not interpolate user parameter values directly into shell scripts.
- [x] Prefer passing parameter values as environment variables.
- [x] If interpolation is unavoidable, escape shell-sensitive characters rigorously.
- [x] Select newly installed snippets by identifier, not by `last`.
- [x] Make template install behavior predictable for vault folders.
- [x] Decide whether templates should be built in or optional examples.

### Phase 7: Plugin System Redesign

- [ ] Do not import the PR plugin system as-is.
- [ ] Decide whether Clipy Classic actually needs plugins in core.
- [ ] If yes, start with manual plugins only.
- [ ] Keep plugins disabled by default.
- [ ] Document the plugin trust model in-app or in docs.
- [ ] Avoid auto-trigger plugins on every clipboard capture unless there is a clear, reviewed use case.
- [ ] If auto-trigger plugins are ever added:
  - [ ] Add explicit user opt-in.
  - [ ] Add rate limiting.
  - [ ] Add concurrency caps.
  - [ ] Add cancellation or stale-result handling.
  - [ ] Add clear warning that clipboard contents are exposed to plugins.
- [ ] Run plugin executables directly with `Process`.
- [ ] Do not build plugin commands through `/bin/bash -c`.
- [ ] Set `currentDirectoryURL` explicitly.
- [ ] Resolve symlinks before validating plugin command paths.
- [ ] Validate command paths stay inside the plugin directory after symlink resolution.
- [ ] Use a minimal explicit environment.
- [ ] Do not pass the full parent process environment by default.
- [ ] Do not pass both `CLIPBOARD` and `CLIPY_INPUT` unless both are deliberately documented.
- [ ] Move filesystem scanning and manifest decoding off the main actor.
- [ ] Add tests for manifest parsing, enable state, path validation, and execution failures.

### Phase 8: Documentation And Release Notes

- [ ] Do not import PR #3's v2.2 changelog entry as-is.
- [ ] Add Clipy Classic release notes only when features land.
- [ ] Use current calendar versioning format: `YY.M.patch`.
- [ ] Keep `goniszewski/Clipy` links.
- [ ] Do not claim releases are signed or notarized unless the release process actually guarantees it.
- [ ] Keep the current Sparkle/manual-release explanation.
- [ ] Update docs only for features that are implemented and verified.
- [ ] Avoid replacing current docs sections with upstream fork copy.

## Do Not Import

- [ ] Whole PR #3 as a merge commit.
- [ ] v2.2 semver release framing.
- [ ] Changelog text that replaces the current v26 release train.
- [ ] Documentation links pointing to `jeanluciradukunda/Clipy`.
- [ ] Claims about signing/notarization that do not match this fork.
- [ ] Any change that reverts Clipy Classic branding.
- [ ] Any change that removes the current Sparkle/manual GitHub release fallback.
- [ ] Any change that removes archive compatibility work.
- [ ] Any broad CI/release workflow rollback caused by branch divergence.
- [ ] Auto-trigger plugin execution without a redesigned security model.
- [ ] Plugin execution through shell command concatenation.
- [ ] Plugin inheritance of full app environment by default.
- [ ] Raw shell interpolation for template parameters.
- [ ] AWS-specific templates as default core templates unless there is a clear product decision.

## Verification Checklist

- [x] Build with `xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug -destination 'platform=macOS' build`.
- [x] Run relevant unit tests.
- [ ] Manually verify plain text snippet paste.
- [ ] Manually verify script snippet paste.
- [ ] Manually verify failed script error display.
- [ ] Manually verify timeout behavior.
- [ ] Manually verify ephemeral output does not appear in history.
- [ ] Manually verify auto-clear does not clear newer user clipboard content.
- [ ] Manually verify menu numbering and keyboard shortcuts.
- [ ] Manually verify snippet editor drag/reorder still works.
- [ ] Manually verify vault folders still hide protected snippet content until unlocked.
- [x] Review final diff for accidental docs, branding, release, or workflow regressions.
