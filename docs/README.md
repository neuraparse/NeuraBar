# NeuraBar docs

Internal project documentation. The user-facing README lives at the repo root.

| File | What's in it |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Module-by-module breakdown, observable graph, persistence layout, menu-bar icon precedence, permissions flow |
| [`FEATURES.md`](FEATURES.md) | Complete feature inventory for every tab + cross-cutting systems (command palette, global hotkey, data location, permissions, localization, keyboard shortcuts) |
| [`TESTING.md`](TESTING.md) | All 292 tests grouped by suite, isolation via `NBTestCase`, guarding rules, performance budgets |
| [`RELEASES.md`](RELEASES.md) | Consolidated changelog from v1.0.0 → v1.3.0, versioning rules, distribution pipeline |
| [`ROADMAP.md`](ROADMAP.md) | Near-term candidates (Google Drive OAuth, CloudKit, ScreenCaptureKit, richer notes blocks, AI tool-use), things already rejected, hard non-goals |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Build / test / release commands, filesystem layout at runtime, conventions, debugging |

Also relevant at the repo root:

- [`CLAUDE.md`](../CLAUDE.md) — concise working notes for Claude Code sessions; loaded automatically.
- [`README.md`](../README.md) — public-facing introduction + install instructions.
