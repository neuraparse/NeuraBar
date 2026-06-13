# Agent memory & handoff

How AI coding agents keep context on NeuraBar — across long sessions, across
compaction, and across different tools (Claude Code, Codex, Cursor, Copilot,
Gemini CLI, …). This is the map; the rules themselves live in the files it points to.

> **TL;DR** — One canonical instruction file ([`AGENTS.md`](../AGENTS.md)), a deep
> Claude companion ([`CLAUDE.md`](../CLAUDE.md)), `docs/` as the durable knowledge
> base, and [`HANDOFF.md`](./HANDOFF.md) as the rolling per-session baton. Tool-specific
> files are thin pointers, not copies.

---

## The layered model

Five layers, each with a single owner. Higher layers are stable; lower layers churn.

| Layer | File(s) | Scope | Maintained by | Churn |
|-------|---------|-------|---------------|-------|
| **1 · Canonical rules** | [`AGENTS.md`](../AGENTS.md) | Every agent, every tool | Humans | Rare |
| **2 · Claude companion** | [`CLAUDE.md`](../CLAUDE.md) | Claude Code (deep, with correction history) | Humans + Claude | Occasional |
| **3 · Project knowledge** | [`docs/`](.) — ARCHITECTURE / FEATURES / TESTING / ROADMAP / DEVELOPMENT / RELEASES | All agents + humans | Humans + agents | Per feature |
| **4 · Session handoff** | [`HANDOFF.md`](./HANDOFF.md) | Whoever picks up next | The **ending** agent | Per session |
| **5 · Personal/user memory** | `~/.claude/.../memory/` (Claude), `~/.codex/` (Codex) | One operator's machine | The tool, auto | Continuous |

Rules of thumb:

- **Don't duplicate across layers.** A fact lives in exactly one layer. Tool
  pointer files (Layer 1 satellites) restate at most the 4–5 highest-risk rules
  and link to the canonical file for the rest.
- **Layer 3 is the source of truth for *what the project is*.** If an agent's
  understanding conflicts with `docs/`, the docs win — or the docs are stale and
  should be fixed in the same change.
- **Layer 4 is ephemeral but on-disk.** It captures *what just happened and what's
  next* so a fresh session (or a different agent) starts warm.

---

## How each tool loads memory

All of these resolve to the **same** canonical content — no tool gets a private
copy of the rules.

| Tool | Reads | Notes |
|------|-------|-------|
| **Claude Code** | `CLAUDE.md` (+ `@imports`), `.claude/` | Deep companion. Falls back to `AGENTS.md` if no `CLAUDE.md`. `/memory` shows what's loaded. |
| **Codex CLI** | `AGENTS.md` (nearest-wins, nested) | Native. Closest `AGENTS.md` to the edited file takes precedence; explicit prompts override all. ~32 KiB cap — keep it lean. |
| **Cursor** | `.cursor/rules/*.mdc` | `neurabar.mdc` (`alwaysApply: true`) + `tests.mdc` (glob-scoped). Both defer to `AGENTS.md`. |
| **GitHub Copilot** | `.github/copilot-instructions.md` | Thin pointer → `AGENTS.md`. |
| **Gemini CLI** | `GEMINI.md` | Thin pointer → `AGENTS.md`. |
| **Aider / Zed / Devin / others** | `AGENTS.md` | The open standard; 30+ agents read it. |

Map of the satellite files:

```
AGENTS.md                          ← canonical, cross-tool (Codex, Aider, Zed, Devin, …)
├── CLAUDE.md                      ← Claude Code (deep companion, correction history)
├── GEMINI.md                      ← Gemini CLI         → points to AGENTS.md
├── .github/copilot-instructions.md ← GitHub Copilot    → points to AGENTS.md
└── .cursor/rules/
    ├── neurabar.mdc               ← Cursor, always-on   → points to AGENTS.md
    └── tests.mdc                  ← Cursor, Tests/** scoped
```

---

## The handoff protocol

The single most useful — and most skipped — technique. As a session approaches
compaction it gets slower and less reliable (attention frays past ~120k tokens).
A handoff moves a clean, structured briefing to disk so the next run starts fresh.

**When to write it**

- Before you `/clear`, compact, or end a substantial session.
- Before switching tools or worktrees (Claude → Codex, or a new branch).
- Whenever you've made decisions the next session would otherwise have to rediscover.

Write it **before** closing the sending session — the ending agent has the context
to brief well; a cold next-session can't reconstruct it.

**What it contains** — five sections (free text within each):

1. **Objective** — what the receiver should accomplish, stated directly (not "continue what we discussed").
2. **Constraints** — conventions, decisions already made, files not to touch, permissions.
3. **Prior decisions** — what was tried, what worked, what was rejected and *why*. The highest-value section.
4. **Current state** — files changed, tests passing/failing, what the code looks like *now*. Point to concrete artifacts.
5. **Next steps** — what remains, in order, with known risks / open questions.

**Where it lives** — [`HANDOFF.md`](./HANDOFF.md), top of file is the `Active
handoff`; superseded entries get pushed into `Archive`. Markdown (not a tool's
native memory) keeps it **portable** — any agent can read it.

**How the next session consumes it** — read `HANDOFF.md` first, treat the
`Active handoff` as opening context, then verify against the live repo (run the
tests, check `git status`) before trusting "Current state".

---

## Hygiene

- **Keep `AGENTS.md` lean** — Codex silently truncates past ~32 KiB; short files
  also get parsed more reliably. Push depth into `docs/`, not into `AGENTS.md`.
- **Edit rules in one place.** Change `AGENTS.md`; let the pointer files forward.
  If you find yourself copying a rule into a satellite, link instead.
- **Fix docs in the same change.** If a code change makes `docs/` wrong, update
  the doc in that change — Layer 3 only stays trustworthy if it's never left stale.
- **Don't put per-session state in Layers 1–3.** "Currently debugging X" belongs in
  `HANDOFF.md`, not `AGENTS.md`/`CLAUDE.md`.
- **Archive, don't accumulate.** `HANDOFF.md`'s `Active handoff` is always the
  *latest* one; move old ones down so the top entry is unambiguous.

---

## See also

- [`AGENTS.md`](../AGENTS.md) — the canonical cross-tool instructions
- [`CLAUDE.md`](../CLAUDE.md) — the deep Claude Code companion
- [`HANDOFF.md`](./HANDOFF.md) — the live session-handoff document
- [`ARCHITECTURE.md`](./ARCHITECTURE.md) · [`FEATURES.md`](./FEATURES.md) · [`TESTING.md`](./TESTING.md) · [`ROADMAP.md`](./ROADMAP.md) · [`DEVELOPMENT.md`](./DEVELOPMENT.md) · [`RELEASES.md`](./RELEASES.md)
