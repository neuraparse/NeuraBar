# GitHub Copilot — NeuraBar

NeuraBar maintains a single, cross-tool canonical instruction file so every agent
shares the same rules.

👉 **Read [`AGENTS.md`](../AGENTS.md) at the repo root.** It covers build/test
commands, code conventions, signing constraints, and commit rules.

## Non-negotiables Copilot must respect

- **Never ship build warnings**; the 292-test suite must stay green.
- Author commits as **Bayram Eker** `<eker600@gmail.com>` — **never** add a
  Claude / AI co-author line.
- Codable stores need **tolerant decoders** — never break JSON already on disk.
- Tests that touch `Persistence` must inherit from `NBTestCase`.
- **No in-app toasts** — user feedback flashes the menu-bar icon (~1.4s).
- New `Loc` keys need an English translation **and** an entry in
  `LocalizationTests`'s `allCases` list.

## Project shape

SwiftUI macOS 14+ menu-bar app, zero dependencies. `@main` + `AppStore` in
`Sources/NeuraBar/NeuraBarApp.swift`; features under `Sources/NeuraBar/Features/`.
Architecture: [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md).

Session continuity: [`docs/HANDOFF.md`](../docs/HANDOFF.md).
