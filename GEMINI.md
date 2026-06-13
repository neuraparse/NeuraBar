# GEMINI.md

NeuraBar keeps **one** canonical instruction file so every agent shares the same
rules. Gemini CLI loads this file — it just forwards you to the real one.

👉 **Read [`AGENTS.md`](./AGENTS.md) first.** It covers build/test commands, code
conventions, ad-hoc-signing constraints, and commit rules, and links to the
deeper docs in [`docs/`](./docs/).

Session continuity lives in [`docs/HANDOFF.md`](./docs/HANDOFF.md); the memory
model is explained in [`docs/AGENT-MEMORY.md`](./docs/AGENT-MEMORY.md).

> Do **not** add rules here — edit [`AGENTS.md`](./AGENTS.md) so all tools stay in sync.
