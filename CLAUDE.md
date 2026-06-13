# NeuraBar — Claude working notes

Ad-hoc signed macOS menu-bar app. SwiftUI, macOS 14+, zero external dependencies. Owned by `neuraparse` on GitHub. Author commits as **Bayram Eker** `<eker600@gmail.com>` — **never add yourself as a co-author** on commits, the user explicitly doesn't want it.

## Subagents live in `.claude/agents/`

Prefer these for sub-tasks; they bake the NeuraBar context in so they don't re-derive it.

- **`neurabar-expert`** — the default for any code work inside this repo. Reading, editing, planning, test writing, bug chasing. Use `Agent(subagent_type: "neurabar-expert", prompt: "...")` for any non-trivial NeuraBar investigation or implementation.
- **`neurabar-releaser`** — release pipeline only. Use when the user says "release", "tagle", "build al", or similar. Knows the exact `ditto -c -k --keepParent` + annotated-tag + `gh release create` sequence.

When you spawn built-in agents (Explore / Plan / general-purpose) for NeuraBar tasks, include doc references in the prompt so they can consult them:

```
Read docs/ARCHITECTURE.md for the module layout, CLAUDE.md for conventions,
and docs/TESTING.md for how the test suite is organised. Then <task>.
```

## Docs are the authoritative state document

- [`AGENTS.md`](./AGENTS.md) — **cross-tool canonical** instructions (Codex, Cursor, Copilot, Gemini, Aider…). This `CLAUDE.md` is the deep Claude companion; both defer to `docs/`. Edit shared rules in `AGENTS.md` so every tool stays in sync.
- [`CLAUDE.md`](./CLAUDE.md) — this file. Conventions, constraints, correction history.
- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — module-by-module breakdown, observable graph, persistence layout.
- [`docs/FEATURES.md`](./docs/FEATURES.md) — complete feature inventory per tab + cross-cutting systems.
- [`docs/TESTING.md`](./docs/TESTING.md) — 292-test suite inventory, `NBTestCase` isolation, guarding rules.
- [`docs/ROADMAP.md`](./docs/ROADMAP.md) — pending, rejected, and hard non-goal decisions. **Check here before re-opening a settled discussion.**
- [`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md) — build / test / release commands, debugging, filesystem layout.
- [`docs/RELEASES.md`](./docs/RELEASES.md) — consolidated changelog v1.0.0 → current.
- [`docs/AGENT-MEMORY.md`](./docs/AGENT-MEMORY.md) — layered agent-memory model + how each tool loads context.
- [`docs/HANDOFF.md`](./docs/HANDOFF.md) — rolling session-handoff baton. **Update its `Active handoff` before ending substantial work** so the next session (any tool) starts warm.

## Build + test

```bash
./build.sh                 # build + produce NeuraBar.app
./build.sh install         # build + copy to /Applications + open

# Tests need full Xcode (not just CLT — XCTest isn't in CLT)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

292 tests pass as of v1.3.0. Builds are clean — **never ship with warnings**.

## Architecture

```
Sources/NeuraBar/
├── NeuraBarApp.swift              @main + AppStore (owns every sub-store)
├── MainView.swift                 Menu-bar popover shell, 9-tab layout
├── WindowManager.swift            Pop-out NSWindow (820×720) + popover↔window mutex, hideAllWindows()
├── CommandPalette.swift           ⌘K fuzzy search
├── Theme.swift                    NB spacing/radius tokens, glass modifier, hover helpers
├── Logo.swift                     NeuraMark shape, LogoView, BrandPulse/Splash/Watermark, MenuBarIconView
├── Localization.swift             Loc enum + EN/TR dictionaries + Localization observable
├── Persistence.swift              JSON read/write + SettingsStore + SettingsSheet
├── DataLocation.swift             User-selectable data directory + migration (iCloud / Google Drive / custom)
├── GlobalHotkey.swift             Carbon ⌘⌥N system-wide
├── MenuBarStatus.swift            Event flash coordinator (copy / recording / automation)
├── NotificationService.swift      UNUserNotificationCenter wrapper, bundle-guarded
├── PermissionsService.swift       Screen recording + microphone TCC helpers + restart
├── PermissionsStore.swift         Observable store + polling + next-action state machine
├── ToastManager.swift             *REMOVED — user didn't want in-app toasts*
└── Features/
    ├── Todos.swift                Priority + due date + hashtag tags + time groups
    ├── Pomodoro.swift             5 modes + streak + goal ring + skip/extend
    ├── Shortcuts.swift            Grid + real app icons + drag reorder + drop zone + color
    ├── Automation.swift           12 automations + run history + structured results
    ├── Clipboard.swift            Persistent history + pin + dedupe + 200 cap
    ├── Notes.swift                Markdown edit/preview + images + time groups + adaptive layout
    ├── NoteAttachments.swift      SHA-256 content-addressed image store + body parser
    ├── System.swift               CPU/RAM/disk/battery + thresholds + alert level
    ├── Recording.swift            Audio via AVAudioRecorder, screen via screencapture -v + options
    ├── RecordView.swift           Source picker sheet + live audio meter + permission banners
    ├── AIProviders.swift          11 CLI detection (cached) + API + desktop hand-off
    ├── AIConversations.swift      ChatGPT-style conversation store with auto-title
    └── Assistant.swift            Sidebar / compact history + streaming + slash commands + approvals
```

## Important contracts

**Codable stores** — every persisted type has a **tolerant decoder** that fills missing fields with defaults. Never break existing JSON on disk. Tests enforce this.

**Persistence.supportDir** — resolves in priority order:
1. `Persistence.overrideDir` (test hook, points at temp dir via `NBTestCase`)
2. `Persistence.userDir` (set by bootstrap from `location.json`)
3. `DataLocationResolver.applicationSupportURL` (fallback)

`location.json` **must stay in Application Support** — it's the pointer to wherever the rest lives. Migration deliberately skips it.

**Menu bar icon precedence** (high → low):
1. Event flash (`MenuBarStatusCoordinator.currentEvent`, ~1.4s)
2. System critical (red pulsing exclamation triangle, persistent)
3. Pomodoro running (phase-tinted timer glyph with variableColor iterative)
4. Base NeuraMark template + optional orange dot overlay for system warning

**Permissions** — `startAudio()` and `startScreen()` both return `Bool` and populate `lastError` on refusal. **Never silently spawn `screencapture` when authorisation is missing** — it'll produce empty files. `.area` and `.systemPicker` hand off to macOS's Screenshot.app entirely.

**Ad-hoc signing limits** — the app can't use iCloud ubiquity containers, CloudKit, or any entitlement that requires a paid Apple Developer ID. Data location uses the plain-folder approach instead (write into iCloud Drive / Google Drive desktop sync folders).

## Conventions

- Don't commit with a Claude co-author line. Ever.
- Don't introduce warnings. Clean build is the baseline.
- Tests that hit `Persistence` must inherit from `NBTestCase` so `overrideDir` redirects to a temp dir.
- L10n keys live in `Localization.swift` with **every** key having an English translation — `LocalizationTests.testEveryLocKeyHasEnglishTranslation` guards this; add new keys to its `allCases` list.
- macOS-API calls that need a real `.app` bundle (UNUserNotificationCenter, CGRequestScreenCaptureAccess) should guard with `Bundle.main.bundlePath.hasSuffix(".app")` — `swift test` runs inside the xctest runner and crashes otherwise.
- The user is Turkish and writes informal/warm messages. Reply in Turkish unless they switch. Be terse — no trailing summaries or over-explanation.

## Releases

- `v1.0.0` initial — 9 tabs + AI conversations + global hotkey + 201 tests
- `v1.1.0` Record tab + global hotkey + animation polish + 228 tests
- `v1.2.0` permissions system + recording source picker + menu bar timer + 268 tests
- `v1.3.0` user-selectable data location (iCloud Drive / Google Drive / custom) + Notion-style image notes + 292 tests

Every release is ad-hoc signed and distributed as `NeuraBar-X.Y.Z.zip` on GitHub Releases. Version lives in both `Info.plist` and the About panel string in `Persistence.swift`.

## Things the user has corrected mid-session — don't re-litigate

- **No in-app toasts.** Feedback must land on the menu bar icon. Clipboard copy / recording saved / automation done / failed all flash the icon for ~1.4s.
- **Notes compact mode must fit in 420px popover.** Single-pane navigation with back button; split view only when width ≥ 520.
- **Contrast on pop-out window**: opaque `windowBackgroundColor` + `regularMaterial`, not `ultraThinMaterial` — the latter disappears over bright wallpapers.
- **Sluggish AI tab**: conversations must be observed via `@EnvironmentObject` so streaming chunks propagate in real time; don't piggy-back on timers.
- **Record tab used to silently record without permission** → permission banners + `Bool` return contract now exist.

## See also

- `AGENTS.md` — cross-tool canonical instructions (the `agents.md` standard)
- `docs/AGENT-MEMORY.md` — layered agent-memory model + handoff protocol
- `docs/HANDOFF.md` — the live session-handoff document
- `docs/ARCHITECTURE.md` — module-by-module breakdown
- `docs/FEATURES.md` — complete feature inventory
- `docs/ROADMAP.md` — what's pending / deliberately skipped
- `docs/TESTING.md` — how the 292-test suite is organised
- `docs/RELEASES.md` — consolidated changelog
