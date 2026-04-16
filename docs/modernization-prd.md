# Clipy Modernization PRD

Last updated: 2026-04-16
Status: Draft
Owner: Maintainers

## 1. Executive Summary

Clipy already runs on a modern macOS baseline and has meaningful UI improvements, but the fork still carries legacy delivery, architecture, and testing debt that slows iteration and hides regressions. This PRD defines the next modernization phase as a focused engineering program: make CI trustworthy, reduce tooling drag, decompose oversized feature surfaces, replace legacy serialization paths, and modernize app lifecycle and tests.

This document is also the progress tracker for the effort. The TODO lists below are intended to be updated in-place as milestones land.

## 2. Problem Statement

The current fork has three main issues:

1. Delivery confidence is lower than it should be.
   CI currently tolerates build failure patterns and does not act as a reliable regression gate.
2. The runtime target is modern, but the codebase and tooling are only partially modernized.
   The project still relies on CocoaPods-era build tooling, legacy serialization, a global service locator, and very large feature files.
3. The current structure makes future product work more expensive.
   Feature additions are likely to increase coupling, test fragility, and build time unless the architecture is tightened first.

## 3. Background and Current State

The current audit identified the following notable constraints:

- CI accepts `xcodebuild ... build || true` and only checks whether an app bundle exists.
  Reference: [ci.yml](/Users/robert/Documents/repos/goniszewski/Clipy/.github/workflows/ci.yml:31)
- The project still depends on CocoaPods for runtime and build-time dependencies.
  Reference: [Podfile](/Users/robert/Documents/repos/goniszewski/Clipy/Podfile:1)
- App composition still centers on `AppDelegate` and a global mutable environment stack.
  References: [AppDelegate.swift](/Users/robert/Documents/repos/goniszewski/Clipy/Clipy/Sources/AppDelegate.swift:69), [AppEnvironment.swift](/Users/robert/Documents/repos/goniszewski/Clipy/Clipy/Sources/Environments/AppEnvironment.swift:17), [Environment.swift](/Users/robert/Documents/repos/goniszewski/Clipy/Clipy/Sources/Environments/Environment.swift:15)
- Several SwiftUI feature files have grown to monolith scale.
  References: [ClipSearchPanel.swift](/Users/robert/Documents/repos/goniszewski/Clipy/Clipy/Sources/Views/SearchPanel/ClipSearchPanel.swift:163), [ModernSnippetsEditor.swift](/Users/robert/Documents/repos/goniszewski/Clipy/Clipy/Sources/Snippets/ModernSnippetsEditor.swift:18), [ModernPreferencesWindow.swift](/Users/robert/Documents/repos/goniszewski/Clipy/Clipy/Sources/Preferences/ModernPreferencesWindow.swift:1)
- Persistence still uses legacy `NSKeyedArchiver` and insecure coding-disabled decoding.
  References: [NSCoding+Archive.swift](/Users/robert/Documents/repos/goniszewski/Clipy/Clipy/Sources/Extensions/NSCoding+Archive.swift:15), [NSUserDefaults+ArchiveData.swift](/Users/robert/Documents/repos/goniszewski/Clipy/Clipy/Sources/Extensions/NSUserDefaults+ArchiveData.swift:16)
- Tests still depend on global state and legacy test frameworks.
  References: [SnippetSpec.swift](/Users/robert/Documents/repos/goniszewski/Clipy/ClipyTests/SnippetSpec.swift:6), [HotKeyServiceSpec.swift](/Users/robert/Documents/repos/goniszewski/Clipy/ClipyTests/HotKeyServiceSpec.swift:9)

## 4. Goals

### Primary Goals

1. Establish reliable build and test gates for all pull requests.
2. Reduce setup and build complexity by modernizing dependency and code-generation tooling.
3. Reduce architectural coupling in core features so new work can ship without expanding monoliths.
4. Replace the most fragile legacy persistence and serialization surfaces.
5. Modernize test infrastructure enough that changes can be validated quickly and deterministically.

### Secondary Goals

1. Improve contributor onboarding time.
2. Reduce CI runtime and local clean-build cost.
3. Make the codebase more ready for Swift concurrency and newer observation patterns.

## 5. Non-Goals

This phase does not aim to:

- Rewrite the app from scratch.
- Replace Realm with SwiftData immediately.
- Fully redesign the UI again.
- Migrate every single legacy API in one pass.
- Block feature work indefinitely while architecture is perfected.

## 6. Success Criteria

The modernization program is considered successful when:

- PRs fail if the app does not build or tests do not pass.
- CI runs deterministic build and test commands without `|| true`.
- Runtime and build tooling no longer depend on CocoaPods-only utilities for core workflows.
- Search panel, snippets editor, and preferences have smaller feature-scoped modules with clearer responsibilities.
- Legacy archive blobs in defaults and file storage have defined migration paths to `Codable`-based models where practical.
- New tests can run without `UserDefaults.standard` and shared global environment state.

## 7. Guiding Principles

- Prefer incremental migrations over large rewrites.
- Stabilize delivery before broad refactors.
- Introduce seams before changing implementations.
- Keep user-visible behavior unchanged unless a task explicitly includes UX improvements.
- Every modernization change should either reduce risk, reduce complexity, or increase iteration speed.

## 8. Workstreams

### Workstream A: Build and CI Integrity

Objective: make CI a real gate.

Expected outcomes:

- Build failures fail CI.
- Tests run in isolated derived data paths.
- Script phases do not rerun unnecessarily on every build.

### Workstream B: Tooling and Dependency Modernization

Objective: reduce pod-driven setup and maintenance overhead.

Expected outcomes:

- Runtime dependencies move to Swift Package Manager where feasible.
- Generated assets/strings rely more on native Xcode features and less on custom scripts.

### Workstream C: Architecture and Module Decomposition

Objective: stop the current large files and global state patterns from expanding.

Expected outcomes:

- Feature-specific services and view models replace broad cross-feature coupling.
- `AppEnvironment` no longer acts as the default access path for most application behavior.

### Workstream D: Persistence and Data Safety

Objective: remove fragile serialization paths and define migrations explicitly.

Expected outcomes:

- Archived defaults and file blobs are audited and migrated.
- Secure, typed data models replace ad hoc archiving where possible.

### Workstream E: Test and Verification Modernization

Objective: make tests isolated, fast, and maintainable.

Expected outcomes:

- Tests use injected defaults and isolated storage.
- New tests use modern conventions.

### Workstream F: Lifecycle and Concurrency Modernization

Objective: align app startup and UI state management with the current platform target.

Expected outcomes:

- Legacy app entry patterns are minimized.
- New UI state uses modern observation and async patterns where appropriate.

## 9. Phased Delivery Plan

### Phase 1: Trust the Build

Scope:

- Fix CI truthfulness.
- Make build scripts incremental.
- Ensure tests can run in isolation.

Rationale:

This is the highest leverage change because every later refactor depends on having a trustworthy signal.

### Phase 2: Remove Tooling Drag

Scope:

- Start SPM migration.
- Reduce or replace pod-managed build tools.
- Audit generated resources and localization flow.

Rationale:

This lowers maintenance cost and unblocks cleaner CI and Xcode-native workflows.

### Phase 3: Decompose Core Features

Scope:

- Split search panel, snippets editor, and preferences into smaller modules.
- Introduce protocol-based service seams.
- Shrink `AppDelegate`.

Rationale:

This contains complexity before additional product features make the architecture harder to unwind.

### Phase 4: Persistence and Test Cleanup

Scope:

- Replace archive-based storage where practical.
- Add migration coverage.
- Move tests toward modern isolated patterns.

Rationale:

This is easier and safer once the architecture has better seams and CI is stable.

### Phase 5: Lifecycle and Observation Cleanup

Scope:

- Modernize entry points and observation model.
- Adopt structured concurrency in touched surfaces.

Rationale:

This should happen once the app’s responsibilities are less centralized.

## 10. Detailed TODO Tracker

Legend:

- `[ ]` Not started
- `[~]` In progress
- `[x]` Done
- `Priority`: P0 critical, P1 high, P2 medium

### A. Build and CI Integrity

- [ ] P0 Replace `build || true` in CI with a failing build step.
- [ ] P0 Add a dedicated `xcodebuild test` CI step using an isolated `-derivedDataPath`.
- [ ] P0 Capture and upload `.xcresult` bundles on CI failures.
- [ ] P1 Make CI validate the actual scheme and product names without relying on `find ~/Library/Developer/Xcode/DerivedData`.
- [ ] P1 Add outputs or dependency-analysis strategy for `SwiftLint`, `SwiftGen`, and `BartyCrouch` script phases.
- [ ] P1 Split CI into at least `build`, `test`, and `lint/generation` concerns.
- [ ] P2 Document the canonical local verification commands in the README or contributor docs.

### B. Tooling and Dependency Modernization

- [ ] P1 Inventory every CocoaPods dependency as `runtime`, `dev-tool`, or `replaceable`.
- [ ] P1 Move `SwiftLint` off CocoaPods and onto a dedicated install path or pinned binary strategy.
- [ ] P1 Move `SwiftGen` off CocoaPods and make generation explicit in local/CI workflows.
- [ ] P1 Evaluate whether `BartyCrouch` should be replaced by string catalogs and Xcode-native localization workflows.
- [ ] P1 Migrate runtime libraries to Swift Package Manager where support is mature.
- [ ] P2 Remove pod-only setup instructions once parity is reached.
- [ ] P2 Delete obsolete pod plumbing and regenerate project guidance after migration.

### C. Architecture and Module Decomposition

- [ ] P0 Define target feature boundaries for Search Panel, Snippets, Preferences, and App Shell.
- [ ] P1 Extract search filtering, quick-select, preview generation, and actions out of `ClipSearchPanel.swift`.
- [ ] P1 Extract snippet persistence, selection state, and vault behaviors out of `ModernSnippetsEditor.swift`.
- [ ] P1 Extract preferences tabs into independent views/models rather than one large window file.
- [ ] P1 Reduce `AppDelegate` responsibilities by moving update, startup, and menu wiring into dedicated coordinators.
- [ ] P1 Replace direct `AppEnvironment.current` access in touched code with explicit dependency injection.
- [ ] P2 Introduce protocols for clipboard, paste, hotkey, and storage services.
- [ ] P2 Add module or folder conventions that prevent new monolith files from forming.

### D. Persistence and Data Safety

- [ ] P1 Audit all uses of `ArchiveCompatibility` and catalog stored payload types.
- [ ] P1 Replace default-stored archived objects with `Codable` representations where practical.
- [ ] P1 Define backward-compatible migration logic for any persisted archive format changes.
- [ ] P1 Add tests covering persistence migration for at least one defaults-backed and one file-backed object.
- [ ] P2 Audit Realm usage patterns and identify which surfaces can become repository-style abstractions first.
- [ ] P2 Decide explicitly whether Realm remains the medium-term store of record.

### E. Test and Verification Modernization

- [ ] P0 Stop relying on `UserDefaults.standard` in new or touched tests.
- [ ] P1 Add isolated defaults suites and explicit Realm configurations for all storage-related tests.
- [ ] P1 Replace `try! Realm()` patterns in tests with helper-based setup that fails clearly.
- [ ] P1 Introduce integration-style tests for core flows: capture clip, search clip, paste clip, save snippet.
- [ ] P2 Evaluate migration from Quick/Nimble to Swift Testing for new tests.
- [ ] P2 Define a testing pyramid so future coverage is intentional rather than ad hoc.

### F. Lifecycle and Concurrency Modernization

- [ ] P1 Design the path from `@NSApplicationMain` to a modern app entry strategy.
- [ ] P1 Replace KVO bridge patterns for defaults observation where a cleaner approach exists.
- [ ] P1 Convert newly touched UI state models from `ObservableObject`/Combine to modern observation where practical.
- [ ] P2 Replace timing hacks based on `DispatchQueue.main.asyncAfter` with explicit async flow or event-driven coordination where possible.
- [ ] P2 Enable stricter concurrency diagnostics once major coupling is reduced.

## 11. Recommended Sequence

The recommended order of execution is:

1. Build and CI Integrity
2. Tooling and Dependency Modernization
3. Architecture and Module Decomposition
4. Persistence and Data Safety
5. Test and Verification Modernization
6. Lifecycle and Concurrency Modernization

This order is intentional. If CI remains permissive, later refactors will produce noisy and unreliable outcomes.

## 12. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| SPM migration breaks contributor workflows | High | Run a staged migration with parallel support until parity is confirmed |
| Feature decomposition changes behavior subtly | High | Add integration tests before extracting critical flows |
| Persistence migration risks data loss | High | Use dual-read or one-time migration strategies with backup/fallback behavior |
| Test modernization expands scope too early | Medium | Migrate tests only after clear seams exist |
| Over-refactoring blocks user-facing work | Medium | Keep work packaged into small PRs with visible checkpoints |

## 13. Open Questions

- Which pods are currently blocked from a clean SPM migration?
- Do maintainers want to keep Quick/Nimble long term, or only for untouched legacy specs?
- Should string catalogs become the default localization path for all new UI strings?
- Is Realm still the preferred medium-term persistence layer, or only a temporary bridge?
- Do we want to enforce file-size or architectural linting rules for large SwiftUI files?

## 14. Progress Snapshot

Update this section whenever a milestone lands.

| Workstream | Status | Notes |
|---|---|---|
| Build and CI Integrity | Not started | CI currently verifies bundle presence rather than true success |
| Tooling and Dependency Modernization | Not started | CocoaPods still owns runtime and build-tool dependencies |
| Architecture and Module Decomposition | Not started | Large feature files and global environment remain central |
| Persistence and Data Safety | Not started | Legacy keyed archiving is still active |
| Test and Verification Modernization | Not started | Tests still depend on global defaults and legacy patterns |
| Lifecycle and Concurrency Modernization | Not started | App shell still relies on older lifecycle patterns |

## 15. Definition of Done

This PRD can be closed when:

- Every P0 item is complete.
- At least one end-to-end CI workflow blocks regressions reliably.
- Core modernization seams are established and documented.
- The progress snapshot shows no workstream in `Not started`.
- Follow-on product work can proceed without expanding the legacy patterns called out here.
