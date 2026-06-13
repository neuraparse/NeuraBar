# Session handoff

The rolling baton between agent sessions. The **ending** agent fills the
`Active handoff` *before* closing a substantial session; the next session (any
tool) reads it first, then verifies against the live repo.

Why this exists, when to write, and the layered memory model:
[`AGENT-MEMORY.md`](./AGENT-MEMORY.md).

> **Protocol**
> 1. Before you `/clear`, compact, switch tools/worktrees, or end a real work
>    session → overwrite `Active handoff` below.
> 2. Move the previous `Active handoff` into `Archive` (newest first).
> 3. Next session: read this, treat `Active handoff` as opening context, then
>    confirm `Current state` with `git status` + the test suite before trusting it.

---

## Template

```markdown
### <ISO date> — <one-line title> — <tool/agent>

**Objective** — What the next agent should accomplish. State it directly.

**Constraints** — Conventions, decisions already locked, files not to touch,
permissions. (Most live in AGENTS.md — only note deltas here.)

**Prior decisions** — What was tried, what worked, what was rejected and why.
The highest-value section; don't make the next session rediscover it.

**Current state** — Branch, version, test status, files changed, what the code
looks like right now. Point to concrete artifacts (paths, commits, PRs).

**Next steps** — What remains, in order, with known risks / open questions.
```

---

## Active handoff

### 2026-06-14 — Agent memory & handoff scaffolding added — Claude Code

**Objective** — Nothing blocking. The cross-tool agent-memory + handoff
structure is now in place; future sessions should *use* it (keep `AGENTS.md`
canonical, update this file before ending substantial work).

**Constraints** — Per [`AGENTS.md`](../AGENTS.md): zero external deps, ad-hoc
signing only, never ship warnings, never add a Claude/AI co-author line, commits
as Bayram Eker `<eker600@gmail.com>`. Don't duplicate rules across the pointer
files — edit `AGENTS.md` and let them forward.

**Prior decisions**
- `AGENTS.md` is the single canonical cross-tool file; `CLAUDE.md` stays as the
  deep Claude companion (kept, not symlinked — its correction history is valuable).
- Cursor / Copilot / Gemini files are **thin pointers**, not copies, to avoid drift.
- Codex needs no extra file — it reads `AGENTS.md` natively (nearest-wins).
- No fabricated `~/.codex/config.toml` / model defaults — that's user-machine
  state (Layer 5), not repo state.

**Current state**
- Branch `main`, version **1.3.0**, **292 tests** green, clean build.
- New, untracked (not yet committed): `AGENTS.md`, `GEMINI.md`,
  `.github/copilot-instructions.md`, `.cursor/rules/{neurabar,tests}.mdc`,
  `docs/AGENT-MEMORY.md`, `docs/HANDOFF.md`; `CLAUDE.md` gained an
  "Agent memory & handoff" pointer block.
- No Swift/source changes — docs/config only, so the test suite is unaffected.

**Next steps**
- Decide whether to commit these files (user hasn't asked to commit yet).
- Real product work is unstarted; near-term candidates live in
  [`ROADMAP.md`](./ROADMAP.md): Google Drive OAuth, ScreenCaptureKit in-app
  recording, Notes block editor (`- [ ]` task lists), Automation AI tool-use,
  Shortcuts groups, Clipboard rich content, Stats/insights.

---

## Archive

_Older handoffs, newest first. (None yet — this is the first.)_
