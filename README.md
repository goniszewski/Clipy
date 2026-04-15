<div align="center">
  <img src="./Resources/clipy_logo.png" width="400">
</div>

<br>

[![CI](https://github.com/goniszewski/Clipy/actions/workflows/ci.yml/badge.svg)](https://github.com/goniszewski/Clipy/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/goniszewski/Clipy)](https://github.com/goniszewski/Clipy/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-brightgreen)](https://github.com/goniszewski/Clipy/releases)

**Clipy Classic** is a clipboard manager for macOS — a modern reimplementation of the original Clipy experience with a SwiftUI interface, Spotlight-style search, syntax highlighting, OCR, smart actions, and more.

> *Built on [Clipy/Clipy](https://github.com/Clipy/Clipy), the original clipboard manager for macOS by [@naotaka](https://github.com/naotaka) and the Clipy Project. This fork is currently maintained by Robert Goniszewski.*

<!-- TODO: Add demo GIF or video recorded with Screen Studio -->
<!-- <p align="center"><img src="./Resources/demo.gif" width="700"></p> -->

---

## Install

### Download

1. Grab the latest `.dmg` from [**Releases**](https://github.com/goniszewski/Clipy/releases/latest)
2. Open the DMG and drag Clipy to Applications
3. Launch Clipy — it appears in your menu bar

> Current GitHub releases may be unsigned and unnotarized until Apple signing credentials are configured. If macOS blocks Clipy, use the Gatekeeper bypass steps below.

### Gatekeeper Bypass for Unsigned Builds

If you're testing a local build or an unsigned release artifact, macOS may block Clipy on first launch.

1. In Finder, open `Applications`
2. Control-click `Clipy.app`
3. Choose `Open`
4. Confirm the warning dialog by clicking `Open` again

If the app is still blocked:

1. Open `System Settings` → `Privacy & Security`
2. Scroll to the security section near the bottom
3. Click `Open Anyway` for Clipy
4. Retry launching the app and confirm the final prompt

This bypass is only needed for unsigned or unnotarized builds. Proper Developer ID-signed releases should launch normally.

### Build from Source

```bash
git clone https://github.com/goniszewski/Clipy.git && cd Clipy
brew install cocoapods
pod install
open Clipy.xcworkspace
# Build (Cmd+B) and Run (Cmd+R) the "Clipy" scheme
```

**Requires**: macOS 14.0 Sonoma+ and Xcode 15.0+

### Versioning

Clipy now uses calendar-based versions in the format `YY.M.patch`.
For example, the release cycle started on April 15, 2026 is `26.4.0`.

### Updating

**Auto-update:** Preferences → Updates → **Check for Updates**. This is available only when the release workflow has a valid Sparkle private key and publishes an appcast.

**Manual:** Download the latest DMG, drag to Applications (replace existing), and launch.

If Gatekeeper blocks the app, follow the unsigned-build bypass steps above.

> Accessibility permission persists across updates — no need to re-grant.

### Release Infrastructure

Clipy's auto-update pipeline uses Sparkle with GitHub-hosted artifacts:

- `docs/appcast.xml` is published via GitHub Pages at `https://goniszewski.github.io/Clipy/appcast.xml` when `SPARKLE_PRIVATE_KEY` is configured
- Sparkle `.zip` update archives are uploaded to GitHub Releases
- `.dmg` archives are uploaded to GitHub Releases for manual installs
- full trust on other Macs requires Developer ID signing and notarization

Required GitHub Actions secrets:

- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_ID_APP_PASSWORD`
- `SPARKLE_PRIVATE_KEY`

`SPARKLE_PRIVATE_KEY` is the private EdDSA key exported from Sparkle's `generate_keys` tool. The public key is embedded in `Info.plist` as `SUPublicEDKey`.

One-time GitHub setup:

1. Enable GitHub Pages for this repository with source `main` and folder `/docs`
2. Bootstrap the Sparkle keypair, update `SUPublicEDKey`, and store the private key as a GitHub secret:
   ```bash
   ./scripts/bootstrap-sparkle-key.sh
   ```
   This uses a repo-specific Sparkle keychain account by default and updates `SPARKLE_PRIVATE_KEY` on the current GitHub repo.
3. If you prefer the manual flow, export the Sparkle private key from your login keychain:
   ```bash
   ./Pods/Sparkle/bin/generate_keys -x /tmp/clipy-sparkle-private-key
   gh secret set SPARKLE_PRIVATE_KEY < /tmp/clipy-sparkle-private-key
   rm /tmp/clipy-sparkle-private-key
   ```
4. Add the Apple signing and notarization secrets listed above

If the Apple signing secrets are not configured yet, the Release workflow falls back to publishing unsigned, unnotarized artifacts. Users can still install them by following the Gatekeeper bypass steps in the Install section above.

If `SPARKLE_PRIVATE_KEY` is missing or empty, the Release workflow skips appcast generation and publishes a manual-download release only.

### Uninstall

1. Quit Clipy (click the menu bar icon → Quit, or `Cmd+Q`)
2. Drag Clipy from Applications to Trash
3. Remove app data (optional):
   ```bash
   rm -rf ~/Library/Application\ Support/com.clipy-app.Clipy/
   defaults delete com.clipy-app.Clipy
   ```
4. Remove from System Settings → Privacy & Security → Accessibility

---

## Features

### Search Panel

A Spotlight-style search panel with split-pane layout: filterable clip list on the left, rich preview + action bar on the right.

- **Fuzzy search** across all clipboard history
- **Content filters**: All, Text, Images, Links, Files, Pinned, Queue
- **Keyboard-driven**: arrow keys to navigate, `Return` to paste, `Shift+Return` for plain text
- **Quick select**: type a number to paste instantly — single digits or two digits rapidly (e.g. `1` `5` for item 15, up to 30)
- **Multi-select**: `Shift+Up/Down` to select multiple clips, `Cmd+Backspace` to bulk delete
- **Pin clips** to keep them at the top (`Cmd+D`)

### Syntax Highlighting

Automatic language detection and syntax highlighting for 16+ languages:
JSON, JavaScript, TypeScript, Python, Swift, Java, HTML, CSS, SQL, Shell, Ruby, Go, Rust, C#, C++, YAML

### OCR

Extract text from image clips using the macOS Vision framework. Click **OCR** when previewing an image — extracted text can be copied directly.

### Smart Actions

The action bar adapts to the selected clip's content type:

**Text clips:**
- **UPPER / lower / Title** — case transforms, copied to clipboard
- **Detected content** — clickable badges for URLs (open browser), emails (compose), phone numbers (call), IP addresses (copy)

**JSON clips:**
- **Format** — pretty-print with indentation for readability
- **Minify** — compress to single line for storage/transport

**URL clips:**
- **Clean URL** — strips tracking parameters (UTM, fbclid, gclid, msclkid, and 50+ others)
- **Clickable preview** — blue underlined URL opens in default browser

**Image clips:**
- **OCR** — extract text from the image using macOS Vision framework
- **Share** — native macOS share sheet (AirDrop, Messages, Mail, other apps)

**Color codes:**
- **Visual swatch** — hex color codes show a color preview in the clip list

### Snippet Picker

Spotlight-style snippet browser with folder navigation, search, and keyboard shortcuts. Type a number to quick-paste by position.

### Snippet Editor

Full-featured SwiftUI snippet editor with:
- Sidebar folder/snippet navigation (arrow keys, expand/collapse)
- Inline rename (double-click)
- Variable insertion toolbar
- Import/export as XML

### Snippet Variables

Dynamic variables that expand at paste time:

| Variable | Output |
|---|---|
| `%DATE%` | Current date (yyyy-MM-dd) |
| `%TIME%` | Current time (HH:mm:ss) |
| `%DATETIME%` | Date + time |
| `%DAY%` | Day of the week |
| `%MONTH%` | Current month name |
| `%YEAR%` | Current year |
| `%TIMESTAMP%` | Unix timestamp |
| `%CLIPBOARD%` | Current clipboard text |
| `%UUID%` | Random UUID |
| `%RANDOM%` | Random 4-digit number |

### Vault Folders

Protect sensitive snippets with Touch ID or password authentication. Vault folders stay locked until you authenticate — hidden from search and the snippet picker until unlocked.

### Clipboard Queue (Collect Mode)

Collect multiple clips and paste them all at once — merged with a configurable separator (newline, comma, tab, space) or pasted one-by-one sequentially.

### Other Features

- **Auto-update** — Sparkle checks the GitHub Pages appcast, downloads signed release archives from GitHub Releases, and installs updates using the standard macOS updater flow
- **Color code detection** with visual swatch preview
- **Exclude apps** from clipboard monitoring
- **Hotkey support** for history, snippets, and snippet folders
- **Auto-launch** on system startup
- **Developer Mode** — toggle in Settings → General unlocking Stats for Nerds (radar chart, hourly/daily activity, feature counters with JSON export), TipKit management, database info, hotkey disable for side-by-side testing, and a vibing Clippy Easter egg
- **TipKit onboarding** — contextual tips in Preferences for feature discovery

---

## Keyboard Shortcuts

Default global hotkeys (configurable in Settings → Shortcuts):

| Shortcut | Action |
|---|---|
| `Shift+Cmd+V` | Open search panel (clipboard history) |
| `Shift+Cmd+B` | Open snippet picker |

### Search Panel

| Shortcut | Action |
|---|---|
| `Up/Down` | Navigate clips (hold to repeat) |
| `Shift+Up/Down` | Extend multi-selection |
| `Return` | Paste selected clip |
| `Shift+Return` | Paste as plain text |
| `1`-`30` (type rapidly) | Quick select by number |
| `Cmd+D` | Pin/unpin clip |
| `Cmd+Backspace` | Delete selected clip(s) |
| `Cmd+O` | OCR — extract text from image |
| `Cmd+S` | Share image via system share sheet |
| `Escape` | Close panel |

### Snippet Picker

| Shortcut | Action |
|---|---|
| `Up/Down` | Navigate folders and snippets |
| `Right` | Expand folder / enter snippets |
| `Left` | Collapse folder / go to parent |
| `Return` | Paste selected snippet |
| `1`-`30` (type rapidly) | Quick select snippet by number |
| `Escape` | Close panel |

### Snippet Editor

| Shortcut | Action |
|---|---|
| `Up/Down` | Navigate sidebar (hold to repeat) |
| `Right` | Expand folder / enter snippets |
| `Left` | Collapse folder / go to parent |
| `Cmd+S` | Save current snippet |
| `Escape` | Close editor |

---

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for full setup instructions.

```bash
brew install cocoapods
pod install
open Clipy.xcworkspace
```

### Dev Build vs Release

Both can coexist on the same Mac with separate data. To run both simultaneously, enable Developer Mode in the dev build's settings and toggle **"Disable Global Hotkeys"** — this prevents hotkey conflicts.

| | **Clipy Classic** (Release) | **Clipy Classic Dev** (Debug) |
|---|---|---|
| Bundle ID | `com.clipy-app.Clipy` | `com.clipy-app.Clipy-Dev.debug` |
| Data directory | `~/Library/Application Support/com.clipy-app.Clipy/` | `~/Library/Application Support/com.clipy-app.Clipy-Dev.debug/` |
| Menu bar | Standard icon | Icon with orange **DEV** badge |
| Settings title | "Clipy Classic Settings" | "Clipy Classic Dev Settings" |
| Install | DMG from Releases | `Cmd+R` in Xcode |
| Accessibility | Persists across updates (Developer ID-signed) | Persists across rebuilds (same local signing identity) |

> **Note for developers:** Both debug builds (local Xcode signing) and release DMGs (Developer ID signing) use a consistent identity, so Accessibility permission persists across updates and rebuilds.

### Debugging

```bash
log stream --process Clipy --predicate 'subsystem == "com.clipy-app.Clipy"' --level debug
```

### Project Structure

```
Clipy/Sources/
├── Models/          # Realm models (CPYClip, CPYFolder, CPYSnippet)
├── Services/        # ClipService, PasteService, HotKeyService, VaultAuthService
├── Views/
│   ├── SearchPanel/       # Search UI, syntax highlighter, content detection
│   └── SnippetPicker/     # Snippet browser panel
├── Snippets/        # Snippet editor
├── Preferences/     # Settings window
├── Extensions/      # Type helpers, NSImage resize
└── Managers/        # Status bar menu
```

---

## Roadmap

See [Issues](https://github.com/goniszewski/Clipy/issues) for the full feature roadmap. Look for `good first issue` labels if you'd like to contribute.

---

## Attribution

Clipy Classic is a fork of [Clipy/Clipy](https://github.com/Clipy/Clipy) (v1.2.1), originally created by the [Clipy Project](https://github.com/Clipy). The current fork is maintained by **Robert Goniszewski**. Special thanks to [@naotaka](https://github.com/naotaka) for publishing the original [ClipMenu](https://github.com/naotaka/ClipMenu) as open source, and to Jean Luc Iradukunda for the intermediate modernization work this fork builds on.

## Star History

<a href="https://www.star-history.com/?repos=goniszewski%2FClipy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=goniszewski/Clipy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=goniszewski/Clipy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=goniszewski/Clipy&type=date&legend=top-left" />
 </picture>
</a>

## License

MIT License. See [LICENSE](LICENSE) for details.

Copyright (c) 2015-2018 Clipy Project
Copyright (c) 2026 Robert Goniszewski
