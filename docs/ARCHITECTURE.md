# Architecture

Module-by-module breakdown. NeuraBar is a single-process, non-sandboxed SwiftUI macOS app. Zero external dependencies — everything is Apple frameworks + Foundation.

## High-level shape

```
┌──────────────────────────────────────────────────────────┐
│                     MenuBarExtra                         │
│   ┌──────────────────────────────────────────────────┐   │
│   │  MainView (menu bar popover — 440×580)           │   │
│   │   ├─ header (logo, ⌘K / ⚙︎ / pop-out / ⏻)      │   │
│   │   ├─ tab content  [Todos / Focus / Shortcuts /   │   │
│   │   │                Automate / Clipboard / Notes /│   │
│   │   │                Record / System / AI]         │   │
│   │   └─ tab bar (⌘1–⌘9)                           │   │
│   └──────────────────────────────────────────────────┘   │
│                                                          │
│   MenuBarIconView  ← reacts to MenuBarStatusCoordinator, │
│   (template glyph)    SystemMonitor.alertLevel,          │
│                       PomodoroTimer.running              │
└──────────────────────────────────────────────────────────┘
                            │
                            │ pop-out ⇲
                            ▼
       ┌──────────────────────────────────────┐
       │ WindowManager.mainWindow             │
       │ (820×720 resizable NSWindow)         │
       │   PoppedMainView(isPoppedOut: true)  │
       └──────────────────────────────────────┘
```

`WindowManager` enforces mutex: opening the big window closes the popover, clicking the menu bar icon while the window is open closes the window. `hideAllWindows()` is called before `screencapture -v` fires so NeuraBar never appears in its own recording.

## AppStore

One owner for all sub-stores. Declared in `NeuraBarApp.swift`. Init order matters:

1. `Persistence.loadDataLocation()` reads the bootstrap pointer from Application Support.
2. `Persistence.applyDataLocation(config)` sets `Persistence.userDir` so every sub-store below reads / writes to the right directory (local, iCloud Drive sync folder, Google Drive folder, or custom).
3. Sub-stores are constructed in a deterministic order.
4. `Localization.shared.apply(override:)` syncs the language from settings.
5. Side-effects: `clipboard.start()` kicks off pasteboard polling, `system.start()` starts the 3-second sampling timer, `registerGlobalHotkey()` wires Carbon ⌘⌥N.

## Persistence

Every feature store uses `Persistence.load(_:from:)` / `save(_:to:)`. File-per-feature layout:

```
<supportDir>/
  location.json                 bootstrap pointer (ALWAYS in Application Support)
  settings.json                 AI keys, language, model preferences
  todos.json                    [TodoItem]
  notes.json                    [NoteItem]
  notes-images/                 SHA-256 content-addressed image files
  clipboard.json                last 200 ClipItems
  shortcuts.json                [ShortcutItem]
  automation_history.json       last 50 AutomationRuns
  conversations.json            AI chat history
  recordings.json               recording metadata
  recording_options.json        record prefs (mic / cursor / notify)
  pomodoro_config.json          pomodoro prefs + daily goal
  pomodoro_sessions.json        last 500 focus sessions
  system_alert_config.json      per-metric thresholds
```

### Tolerant decoders

Every Codable struct has a custom `init(from:)` that reads each field with `try? c.decode(...)` and falls back to a default. This lets us add new fields to stores without breaking users on older `.json` files. Tests in `*Tests.swift` cover both the "legacy JSON missing fields" and the "empty `{}`" cases.

## Data location

`DataLocation.swift` decouples persistence from hard-coded paths. Four modes:

- `.applicationSupport` — `~/Library/Application Support/NeuraBar/`
- `.iCloudDrive` — `~/Library/Mobile Documents/com~apple~CloudDocs/NeuraBar/`
- `.googleDrive` — `~/Library/CloudStorage/GoogleDrive-*/My Drive/NeuraBar/` or legacy `~/Google Drive/NeuraBar/`
- `.custom` — any folder the user picks

`DataLocationResolver` probes availability (e.g. does the iCloud Drive desktop client exist on this Mac?) and falls back to Application Support when it doesn't. `migrate(from:to:)` copies every JSON + `notes-images/` subtree but **deliberately skips `location.json`** — the bootstrap pointer must stay put.

### Why not CloudKit

Apple's first-party iCloud story (ubiquity containers + CloudKit) is restricted to apps distributed through the Mac App Store with a paid Apple Developer ID. NeuraBar ships ad-hoc signed, so CloudKit isn't an option. The folder-based approach works because the third-party sync daemons (iCloud Drive desktop, Google Drive desktop) don't need any help from the app — they just watch their directories.

## Observability

SwiftUI `@ObservableObject` + `@Published` across every store. The app-level state graph:

```
AppStore (no @Published; just holds refs)
   ├── TodoStore           @Published items
   ├── NoteStore           @Published items
   ├── PomodoroTimer       @Published phase / remaining / running / sessions
   ├── ClipboardManager    @Published items
   ├── SystemMonitor       @Published cpu / memory / disk / battery / alertLevel
   ├── ShortcutStore       @Published items
   ├── SettingsStore       @Published data
   ├── AutomationStore     @Published history / runningTaskID
   ├── RecordingStore      @Published recordings / isRecordingAudio / isRecordingScreen / audioLevel
   └── AIConversationStore @Published items / currentID
```

Every sub-store is injected as an `@EnvironmentObject` at the scene level (`NeuraBarApp.body`) and at the window-manager pop-out (`WindowManager.openMainWindow`). Streaming AI chunks were sluggish before conversations were exposed as their own environment object — lesson: don't pipe observable state through a non-observable parent.

## Menu bar icon

`MenuBarIconView` observes three sources and picks the highest-priority glyph:

| Priority | Source | What shows |
|---|---|---|
| 1 | `MenuBarStatusCoordinator.currentEvent` | Colored event glyph (copy / recording / automation) with `symbolEffect(.bounce)` — ~1.4 s |
| 2 | `SystemMonitor.alertLevel == .critical` | Red `exclamationmark.triangle.fill` with `symbolEffect(.pulse, .repeating)` |
| 3 | `PomodoroTimer.running` | Phase-tinted `timer` symbol (purple / green / teal) with `variableColor.iterative` |
| 4 | — | Template NeuraMark + optional orange dot overlay when `alertLevel == .warning` |

The base NeuraMark is rendered once via `ImageRenderer` to an NSImage flagged `isTemplate = true`, so macOS handles light/dark adaptation. The overlay dot is a regular SwiftUI `Circle` so it stays orange/red in both modes.

## Permissions

`PermissionsService` wraps `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` for screen recording and `AVCaptureDevice.authorizationStatus` / `requestAccess` for the microphone. `PermissionsStore` polls both every 1.5 s via a `Timer` (TCC doesn't emit notifications) and tracks a `screenRecordingNeedsRestart` flag — macOS often needs a relaunch after a Settings toggle before the running process picks up the new permission.

The state machine exposed by `PermissionsStore.nextScreenRecordingAction` drives the single button in the `PermissionsBanner`: **Allow** / **Open System Settings** / **Restart**. `PermissionsService.restartApp()` spawns a new instance via `open -n` and terminates the current process after 0.4 s.

## AI

Providers are classified into three kinds (`AIProvider.Kind`):

- `.cli` — local streaming (Claude Code, Codex, Aider, opencode, Gemini, Amp, Goose, Qwen, Plandex, Continue, Ollama). Invoked via `Process` spawning the binary; stdout is piped into the conversation.
- `.api` — HTTP: Anthropic `/v1/messages` and OpenAI `/v1/chat/completions`.
- `.desktop` — hand-off: copies the prompt to the pasteboard, opens the desktop app, inserts a system message in the chat.

`AIDetector.which` caches results per session to avoid spawning a login-shell `zsh` subprocess every time the AI tab opens. First-session open is still slow when no CLIs are installed; subsequent opens are instant. The manual refresh button in the provider bar calls `invalidateWhichCache()` then re-runs detection.

`AIConversationStore` is a separate observable piece so streaming chunks can propagate without triggering a full view tree invalidation. Auto-title picks the first user message's first line, capped at 40 chars.

## Notes

`NoteAttachments` stores images under `notes-images/` with filenames derived from the SHA-256 of the bytes — so the same screenshot embedded in ten notes takes one disk slot. `NoteBodyParser` splits note bodies into `[text, image]` blocks so the preview pane can render images inline alongside markdown-styled text.

Drag-drop uses `.dropDestination(for: URL.self)` and `.dropDestination(for: Data.self)`. Paste reads from `NSPasteboard.general.data(forType: .tiff)` and converts to PNG before storing.

## Testing

`Tests/NeuraBarTests/TestSupport.swift` defines `NBTestCase` which overrides `Persistence.overrideDir` to a unique temp directory in `setUp` and cleans it in `tearDown`. Tests that hit any store must inherit from it.

292 tests as of v1.3.0. See `TESTING.md` for the inventory.
