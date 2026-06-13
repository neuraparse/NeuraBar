# AGENTS.md — NeuraBar

> Portable instructions for **any** coding agent — Codex, Cursor, GitHub Copilot,
> Gemini CLI, Aider, Zed, Devin, **and** Claude Code. This is the cross-tool
> canonical file (the `agents.md` open standard). Claude Code users get a deeper
> companion in [`CLAUDE.md`](./CLAUDE.md); both defer to the same authoritative
> docs in [`docs/`](./docs/). Edit rules **here** so every tool stays in sync.

## Project overview

NeuraBar is an ad-hoc-signed macOS **menu-bar app**. SwiftUI, **macOS 14+**,
**zero external dependencies**. Owned by `neuraparse` on GitHub. Current version
**1.3.0** (292 tests passing).

- `@main` + `AppStore` (owns every sub-store) live in `Sources/NeuraBar/NeuraBarApp.swift`.
- Each feature is an `ObservableObject` store under `Sources/NeuraBar/Features/`.
- Module-by-module map: [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).
  Feature inventory: [`docs/FEATURES.md`](./docs/FEATURES.md).

## Build & test

```bash
./build.sh                 # build (release) → NeuraBar.app
./build.sh install         # build → copy to /Applications + open

# Tests need full Xcode — XCTest is NOT in the CLT-only toolchain:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Single test:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter NeuraBarTests.<TestClass>/<testMethod>
```

- **Never ship with warnings.** A clean build is the baseline.
- 292 tests pass as of 1.3.0. Don't merge red.

## Code style & conventions

- Match the surrounding code's idiom, naming, and comment density. SwiftUI views +
  Combine `ObservableObject` stores; no third-party packages.
- **Codable stores must have tolerant decoders** that fill missing fields with
  defaults — never break JSON already written to disk. Tests enforce this.
- Localization keys live in `Sources/NeuraBar/Localization.swift`. **Every** key
  needs an English translation and must be added to `LocalizationTests`'s
  `allCases` list (a test guards it).
- macOS APIs that need a real `.app` bundle (notifications, screen-capture access)
  must guard with `Bundle.main.bundlePath.hasSuffix(".app")` — `swift test` runs
  inside the xctest runner and crashes otherwise.
- **No in-app toasts.** User feedback lands on the menu-bar icon (~1.4s flash):
  copy / recording-saved / automation-done / failed.

## Testing instructions

- Suite lives in `Tests/NeuraBarTests/`, target `NeuraBarTests`.
  Full inventory + isolation rules: [`docs/TESTING.md`](./docs/TESTING.md).
- Any test that touches `Persistence` **must** inherit from `NBTestCase` so
  `Persistence.overrideDir` redirects reads/writes to a temp dir.

## Security & signing constraints

- **Ad-hoc signing only** — no iCloud ubiquity containers, CloudKit, or any
  entitlement requiring a paid Apple Developer ID. Data lives in plain folders
  (including iCloud Drive / Google Drive desktop-sync folders).
- `location.json` **must stay in Application Support** — it's the pointer to
  wherever the rest of the data lives. Migration deliberately skips it.
- **Never silently spawn `screencapture` when authorization is missing** — it
  produces empty files. `startAudio()` / `startScreen()` return `Bool` and set
  `lastError` on refusal.
- No secrets in the repo. API keys are user-entered at runtime, never committed.

## Commit & PR guidelines

- Author commits as **Bayram Eker** `<eker600@gmail.com>`.
- **Never add a Claude / AI co-author line.** The user explicitly forbids it.
- Branch off `main`; short, imperative messages.
- The version string lives in **both** `Info.plist` and the About panel string in
  `Persistence.swift` — bump them together. Release pipeline (ditto zip +
  annotated tag + `gh release create`) is in [`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md).

## Session memory & handoff

Long or multi-agent work uses a markdown memory + handoff protocol so context
survives session boundaries **and** tool switches (Claude → Codex → Cursor → …):

- **[`docs/AGENT-MEMORY.md`](./docs/AGENT-MEMORY.md)** — the memory architecture:
  which file holds what, the layered model, and how each tool loads context.
- **[`docs/HANDOFF.md`](./docs/HANDOFF.md)** — the rolling session-handoff doc.
  **Before** you end a substantial session, update its `Active handoff` entry
  (Objective / Constraints / Prior Decisions / Current State / Next Steps). The
  next agent reads it first.

## Authoritative docs

`docs/` is the source of truth — read before re-opening a settled question:

| Doc | What it holds |
|-----|---------------|
| [`ARCHITECTURE.md`](./docs/ARCHITECTURE.md) | Module layout, observable graph, persistence |
| [`FEATURES.md`](./docs/FEATURES.md) | Per-tab feature inventory + cross-cutting systems |
| [`TESTING.md`](./docs/TESTING.md) | 292-test suite, `NBTestCase` isolation, guarding rules |
| [`ROADMAP.md`](./docs/ROADMAP.md) | Pending / rejected / hard non-goals — check before re-litigating |
| [`DEVELOPMENT.md`](./docs/DEVELOPMENT.md) | Build / test / release / debug commands |
| [`RELEASES.md`](./docs/RELEASES.md) | Consolidated changelog v1.0.0 → current |
| [`AGENT-MEMORY.md`](./docs/AGENT-MEMORY.md) | How agent memory & handoff work across tools |
| [`HANDOFF.md`](./docs/HANDOFF.md) | The live session-handoff document |
