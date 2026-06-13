# Releases

Consolidated changelog for NeuraBar. All releases are ad-hoc signed, distributed as `NeuraBar-X.Y.Z.zip` on the [GitHub Releases page](https://github.com/neuraparse/NeuraBar/releases).

## v1.3.0 — 2026-04-19

**User-selectable data directory + Notion-style image notes**

- Pick where NeuraBar keeps its data in **Settings → General → Data location**. Auto-detects iCloud Drive desktop sync + Google Drive desktop client; custom folder for anything else.
- Changing the location migrates todos, notes, clipboard history, automation history, conversations, recordings metadata, and the `notes-images/` subtree. Bootstrap pointer (`location.json`) always lives in Application Support.
- **Drag-drop images** onto the notes editor. Content-addressed storage dedupes identical bytes via SHA-256. Preview pane renders images inline.
- Paste image button handles TIFF / PNG / URL from clipboard.
- Markdown `![alt](filename)` is the on-disk representation so notes stay readable outside NeuraBar.
- Does **not** require Apple Developer entitlements — writes into whatever folder the third-party sync daemons are watching.

Tests: 268 → **292** (+24 across `DataLocationTests`, `NoteAttachmentsTests`).

## v1.2.0 — 2026-04-19

**Permissions, recording source picker, menu bar timer indicator, crash-vector cleanup**

- New `PermissionsService` + `PermissionsStore` for Screen Recording + Microphone.
- Live status polling via `Timer`, deep-links to Privacy panes, one-click Restart when macOS has cached old TCC state.
- `PermissionsBanner` at the top of the Record tab — pulsing red for denied, orange for not-asked, blue for grant-needs-restart, hidden when good.
- `startAudio` / `startScreen` return `Bool` and surface errors; no more silently spawning `screencapture` when macOS would drop the result.
- **Start Screen** opens a source picker sheet with iconified tiles: Full Screen / Area / macOS Screenshot toolbar. Area + system picker hand off to macOS because `screencapture -i -v` isn't a valid combination on macOS 26.
- Before capture starts, `WindowManager.hideAllWindows()` closes popover + pop-out so NeuraBar never appears in the recording.
- **Menu bar indicator** now shows a phase-tinted `timer` glyph while Pomodoro is running (focus purple · short break green · long break teal) with `symbolEffect(.variableColor.iterative, .repeating)`.
- Precedence chain: event flash > system critical > pomodoro running > base glyph + optional warning overlay.
- Crash fixes: `PermissionsStore` polling switched from `Task` loop to main-thread `Timer`; `SymbolEffect` ternary replaced by `isActive` form.

Tests: 228 → **268** (+40 across `PermissionsTests`, `RecordFlowTests`, `MenuBarStatusTests`, `MenuBarIconPrecedenceTests`, `SystemAlertTests`, `RecordingSourceTests`, etc.).

## v1.1.0 — 2026-04-19

**AI performance, Record tab, global hotkey, conversations, animation polish**

- `AIDetector.which` cached per session — AI tab opens are instant after the first probe. Previously spawned a login-shell `zsh` subprocess for every missing CLI (0.5–1.2 s block).
- Conversations injected as `@EnvironmentObject` so streaming chunks propagate in real time instead of piggy-backing on a 1-second timer.
- Sending indicator uses `TimelineView` — invalidates only the elapsed-seconds `Text`, not the whole view tree.
- ChatGPT-style persistent conversations: sidebar (wide) / overlay history (compact), auto-title, rename / pin / duplicate / delete.
- Tasks: priority / due date / `#hashtag` tags / search / progress ring / time-grouped list.
- Shortcuts: drag-reorder, Finder drop zone, `/Applications` multi-import, per-shortcut color, ⌘1–⌘9 quick launch, edit sheet.
- Focus: 5 preset modes + custom, skip / +5 min, streak / today / goal ring, phase-aware colors, big timer in pop-out, auto-start toggles.
- Notes: markdown preview toggle (⌘/), toolbar, word / char / reading-time counters with numeric transitions, `#tag` extraction, time groups, color stripes, adaptive layout.
- Record tab (⌘7): audio via `AVAudioRecorder`, screen via `screencapture -v`, live timer, persistent history.
- System: per-metric thresholds, alert levels, menu bar badge on critical, OS notification on first critical transition.
- Feedback moved out of in-app toasts entirely. Every event now flashes the menu bar icon.
- `MenuBarStatusCoordinator.flash(event)` for transient events (copy / recording saved / automation done / failed).
- Global hotkey ⌘⌥N via Carbon (no Accessibility permission).

Tests: 201 → **228** (+27).

## v1.0.0 — 2026-04-19

**Initial public release**

- 9 tabs: Tasks, Focus, Shortcuts, Automate, Clipboard, Notes, Record, System, AI.
- 11 coding CLIs auto-detected (Claude Code, Codex, Aider, opencode, Gemini, Amp, Goose, Qwen Code, Plandex, Continue, Ollama) + Claude / ChatGPT / Codex / Atlas desktop hand-off + Anthropic / OpenAI APIs.
- Slash-command automations with approval for destructive actions; 12 built-in automations with structured run history.
- Command palette (⌘K), ⌘1–⌘8 tab jumps, pop-out big window, global hotkey ⌘⌥N.
- Audio + screen recording, 5 Pomodoro modes + custom, drag-reorder shortcuts with drop zone.
- EN + TR localization.

Tests: **201** XCTest cases.

## Versioning

Semantic-ish:

- **Major** — intentionally-breaking user data or UX. (None so far.)
- **Minor** — new features, new tabs, new capabilities.
- **Patch** — bug-fix only. (Skipped so far; every release has carried new features.)

Build number (`CFBundleVersion`) increments monotonically: 1, 2, 3, 4…

## Distribution

- `./build.sh` produces `NeuraBar.app` with ad-hoc signing.
- Release zip: `/usr/bin/ditto -c -k --keepParent NeuraBar.app dist/NeuraBar-X.Y.Z.zip` — preserves macOS metadata.
- `gh release create vX.Y.Z dist/NeuraBar-X.Y.Z.zip --title ... --notes ...`
- Gatekeeper warning on first launch because we're not notarized. Users need **System Settings → Privacy & Security → Open Anyway**.
