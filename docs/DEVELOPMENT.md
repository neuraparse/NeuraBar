# Development

Quick reference for working on NeuraBar.

## One-time setup

1. macOS 14+ (tested on macOS 26 Tahoe)
2. Xcode Command Line Tools: `xcode-select --install`
3. Full Xcode for running tests (Command Line Tools don't include XCTest framework):
   - Install from App Store or `xcodes install 16.3`
   - Either `sudo xcode-select -s /Applications/Xcode.app` (persistent) or prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` on every `swift test` call (one-off)

## Build

```bash
./build.sh                 # builds .app in the repo root
./build.sh install         # builds + copies to /Applications + opens it
```

Iteration loop:

```bash
killall NeuraBar
./build.sh install
# watch the menu bar
```

## Test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

All 292 tests should pass in ~6 s. A failing test blocks the release pipeline — every release tag has been cut from a green tree.

## Release

```bash
# 1. Bump version in Info.plist and Persistence.swift (About panel)
# 2. Commit as Bayram Eker with no Claude co-author line
git -c user.name="Bayram Eker" -c user.email="eker600@gmail.com" commit -am "Bump to X.Y.Z"

# 3. Clean build + package
rm -rf .build NeuraBar.app dist
./build.sh
mkdir -p dist
/usr/bin/ditto -c -k --keepParent NeuraBar.app dist/NeuraBar-X.Y.Z.zip

# 4. Annotated tag with release notes inline
git -c user.name="Bayram Eker" -c user.email="eker600@gmail.com" tag -a vX.Y.Z -m "NeuraBar X.Y.Z

[release notes here]"

# 5. Push
git push origin main
git push origin vX.Y.Z

# 6. GitHub release
gh release create vX.Y.Z dist/NeuraBar-X.Y.Z.zip --title "NeuraBar X.Y.Z" --notes "..."
```

Use `ditto -c -k --keepParent` (not `zip`) so macOS metadata and the `.app` bundle structure survive the round trip.

## Conventions

### Commits

- **Author**: Bayram Eker `<eker600@gmail.com>`
- **No Claude / AI co-author line.** The user opts out of this by policy.
- Conventional prefixes are fine (`feat:`, `fix:`) but the automated pipeline doesn't parse them. Write for humans.

### Code

- Swift 5.9 target, macOS 14 minimum.
- No warnings. Swift 6 concurrency warnings are non-negotiable.
- Every Codable type that lives in a JSON file on disk needs a tolerant decoder that fills missing fields with defaults. Add a test when you add a field.
- Views that read from stores must do so via `@EnvironmentObject` so SwiftUI's dependency tracking re-renders cleanly.
- macOS APIs that require a real `.app` bundle (UNUserNotificationCenter, `CGRequestScreenCaptureAccess`) must guard with `Bundle.main.bundlePath.hasSuffix(".app")`. `swift test` doesn't run inside a .app bundle.

### Localization

Every user-visible string goes through `Localization.shared.t(.key)` or `L.t(.key)`:

1. Add a case to `Loc` enum in `Localization.swift`
2. Add the English translation in the `Dict.en` dictionary
3. Add the Turkish translation in the `Dict.tr` dictionary
4. Add the case to `LocalizationTests.testEveryLocKeyHasEnglishTranslation`'s `allCases` array

The test fails loud if any of those steps is missed.

### Tests

- Tests that touch `Persistence` must inherit from `NBTestCase` so the temp-dir redirect works.
- `@MainActor` tests use `@MainActor final class SomeTests: XCTestCase { override func setUp() async throws { ... } }`.
- See `docs/TESTING.md` for the full suite inventory and guarding rules.

## Filesystem layout at runtime

Whatever directory the user selected (default `~/Library/Application Support/NeuraBar/`):

```
<supportDir>/
  settings.json
  todos.json
  notes.json
  notes-images/<sha256>.{png,jpg,heic,...}
  clipboard.json
  shortcuts.json
  automation_history.json
  conversations.json
  recordings.json
  recording_options.json
  pomodoro_config.json
  pomodoro_sessions.json
  system_alert_config.json
```

Always in Application Support regardless of the user's data-location choice:

```
~/Library/Application Support/NeuraBar/
  location.json     ← bootstrap pointer — NEVER migrate
```

Recordings themselves live in `~/Downloads/NeuraBar Recordings/`. The `recordings.json` metadata file follows the normal data-location rules.

## Known constraints

- **Ad-hoc signing** means we can't use iCloud ubiquity containers, CloudKit, App Store distribution, or any entitlement that requires a paid Apple Developer ID.
- **First-run TCC prompts** may require a NeuraBar restart after the user grants permission in System Settings (macOS caches state per-process). The permission banner in the Record tab handles this via a **Restart** button.
- **Screen recording window / area selection** — `screencapture` doesn't combine `-v` with `-i` or `-w` on macOS 26. Those modes hand off to macOS's Screenshot.app.
- **No sandboxing.** Hard non-goal. See `ROADMAP.md#non-goals`.

## Debugging

Live process logs:

```bash
PID=$(pgrep -f "/Applications/NeuraBar.app/Contents/MacOS/NeuraBar" | head -1)
/usr/bin/log show --style compact --predicate "processIdentifier == $PID" --last 30s | head -40
```

Crash reports:

```bash
ls -lt ~/Library/Logs/DiagnosticReports/ | head -10
```

Reset permissions if TCC gets confused:

```bash
tccutil reset ScreenCapture
tccutil reset Microphone
```

Reset all user data (destroys notes, todos, clipboard history, etc.):

```bash
rm -rf ~/Library/Application\ Support/NeuraBar/
```
