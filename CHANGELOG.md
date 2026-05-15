# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and starting on April 15, 2026 this project uses calendar-based versions in the format `YY.M.patch`.

## [Unreleased]

## [26.5.3] - 2026-05-15

### Fixed
- Restored snippet editor drag and drop in packaged builds by declaring the private drag payload type and adding a standard text fallback while keeping Clipy-only payload validation.
- Fixed the snippets editor top-right window controls so the close button and `DEV` badge no longer overlap snippet header content.

## [26.5.2] - 2026-05-14

### Fixed
- Fixed manual release packaging so non-Developer ID builds are still locally code-signed with the `com.clipy-app.Clipy` bundle identity, allowing macOS Accessibility permission to attach to the app instead of an ad hoc executable signature.

## [26.5.1] - 2026-05-14

### Added
- Added script snippets with configurable shell, timeout, and ephemeral output settings
- Added script snippet execution from the classic menu, modern snippet picker, and snippets editor test-run flow
- Added script snippet test controls that show stdout, stderr, exit code, timeout state, and launch errors
- Added an ephemeral paste auto-clear preference with Off, 15 second, 30 second, and 60 second options
- Added a script template gallery with JSON formatting, Base64, URL encoding, JWT payload decoding, epoch conversion, UUID generation, and password generation examples
- Added XML import/export support for script snippet fields
- Added script snippet indicators in menus and the modern snippet picker

### Changed
- Routed text and script snippet pasting through a shared snippet execution service
- Hardened script execution with bounded timeouts, output limits, non-zero exit handling, pipe draining, and a minimal documented environment
- Kept ephemeral script output out of clipboard history while avoiding auto-clear of newer clipboard contents

### Fixed
- Fixed history menu overflow layout so inline and submenu placement honors menu size preferences
- Fixed list numbering so the 10th visible item displays as `10.` while keeping the `0` shortcut

## [26.5.0] - 2026-05-13

### Added
- Added a visible close button to the modern snippets editor window
- Added drag reordering for snippet folders and snippets, including moving snippets between folders
- Added insertion-line previews that show where dragged folders or snippets will land

### Changed
- Improved inline rename fields so edit mode and cursor focus are visible

### Fixed
- Surfaced manual GitHub release update-check failures in Preferences instead of failing silently
- Kept snippets editor selection state in sync when selecting snippets across folders or deleting folders
- Restricted snippet reorder drop targets to Clipy's own drag payloads so unrelated text drags are ignored

## [26.4.5] - 2026-04-17

### Added
- Added a GitHub Releases fallback in Preferences so unsigned or manual-install builds can still check for and open the latest release

### Changed
- Expanded history menu keyboard navigation so numbered parent ranges can be selected directly and `Backspace` or `Left Arrow` returns to the parent menu

## [26.4.4] - 2026-04-16

### Fixed
- Disabled Sparkle in manual or debug builds that do not carry a Developer ID signature, avoiding invalid in-app update prompts
- Stopped publishing Sparkle appcasts for unsigned releases, which Sparkle rejects as improperly signed updates

## [26.4.3] - 2026-04-16

### Changed
- Modernized the build, CI, and update workflow around explicit repo scripts and the GitHub Pages-hosted appcast setup
- Xcode builds now skip `SwiftLint`, `SwiftGen`, and `BartyCrouch` by default; run the repo scripts explicitly when you want linting or generated outputs

## [26.4.2] - 2026-04-16

### Fixed
- Kept the Sparkle updater in a ready state after a manual update check by distinguishing an active check from a real updater configuration problem

## [26.4.1] - 2026-04-16

### Fixed
- Restored automatic paste after selecting a history item when macOS grants event-posting permission but the legacy Accessibility trust check remains false

## [26.4.0] - 2026-04-15

### Changed
- Switched the app and release train to calendar-based versioning (`YY.M.patch`)
- Switched auto-updates to Sparkle 2 using a GitHub Pages-hosted appcast and signed update archives
- GitHub Releases now host the signed update downloads instead of acting as the update check source

## [26.3.0] - 2026-03-19

### Added
- **Spotlight-style search panel** — split-pane UI with filterable clip list, rich preview, and action bar
- **Syntax highlighting** — automatic language detection for 16+ languages in preview pane
- **OCR** — extract text from image clips using macOS Vision framework
- **Image share button** — native macOS share sheet for image clips (AirDrop, Messages, etc.)
- **Smart clip actions** — contextual buttons based on content type (URL clean, JSON format/minify, text transforms)
- **Content detection** — auto-detects URLs, emails, phone numbers, IP addresses with clickable badges
- **Snippet picker panel** — Spotlight-style snippet browser with folder navigation and search
- **Modern snippets editor** — SwiftUI editor with arrow key navigation, inline rename, import/export
- **Snippet variables** — 10 dynamic variables (`%DATE%`, `%TIME%`, `%MONTH%`, `%YEAR%`, `%TIMESTAMP%`, `%CLIPBOARD%`, `%UUID%`, `%RANDOM%`, and more) that expand at paste time
- **Vault folders** — Touch ID / password-protected snippet folders using LocalAuthentication
- **Clipboard queue (Collect Mode)** — collect multiple clips, paste merged or sequentially
- **Modern preferences window** — SwiftUI settings with General, Shortcuts, Exclude Apps, Updates tabs
- **Pin clips** — keep important clips at the top (`Cmd+D`)
- **Multi-select** — `Shift+Up/Down` to select multiple clips, bulk delete with `Cmd+Backspace`
- **Two-digit quick select** — type two numbers rapidly to select items beyond 9
- **Color code detection** — visual swatch preview for hex colors
- **Clickable URL previews** — blue underlined links open in default browser
- **Window-level shadows** — clean rounded window appearance without border artifacts
- **Auto-update** — downloads `.dmg` from GitHub Releases, installs, and relaunches
- **Developer Mode** — TipKit management, database info, hotkey disable, Clippy Easter egg
- **Dev build cosmetics** — orange DEV badge on menu bar and all panels, separate app name "Clipy Dev"
- **Side-by-side builds** — release and debug can run simultaneously with separate data

### Changed
- Minimum macOS version raised to 14.0 (Sonoma)
- Rebuilt all UI in SwiftUI (search panel, snippet editor, snippet picker, preferences)
- Windows use borderless/titled style with transparent hosting views for clean rounded corners
- Arrow key navigation supports hold-to-repeat in all panels
- Pinned clips preserved when re-copying the same content
- Realm schema migrated to v10 (added `isPinned` and `ocrText` to CPYClip, `isVault` to CPYFolder)

### Attribution
Clipy Classic is a fork of [Clipy/Clipy](https://github.com/Clipy/Clipy) (v1.2.1), originally created by the Clipy Project. The current fork is maintained by Robert Goniszewski and builds on earlier modernization work by Jean Luc Iradukunda. See [LICENSE](LICENSE) for details.
