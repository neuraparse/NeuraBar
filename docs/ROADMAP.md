# Roadmap

What could come next, grouped by rough priority. Nothing here is committed — these are directions we've considered or touched and deferred.

## Near-term candidates

### Cloud: Google Drive OAuth

1.3.0 ships folder-based sync. A "real" Google Drive integration would need:

- OAuth 2.0 client credentials (user needs a Google Cloud project)
- Browser redirect + custom URL scheme handler
- Token storage + refresh
- Drive API v3 calls for upload / list / download
- Conflict handling when the same file is edited on two devices

~400–600 lines of new code plus credential management. Worth it for true cross-device sync that doesn't depend on a desktop client being installed.

### iCloud via CloudKit

Requires a paid Apple Developer ID ($99/year) and App Store distribution. Unlocks:

- `NSPersistentCloudKitContainer` for structured sync
- Per-record conflict resolution
- Private database tied to the user's Apple ID

Not possible while NeuraBar ships ad-hoc signed. Park this until signing changes.

### ScreenCaptureKit for in-app window / area recording

Current `.area` and `.systemPicker` paths both hand off to macOS's Screenshot.app. Rolling our own via ScreenCaptureKit would let us:

- Record specific windows without leaving NeuraBar
- Draw a SwiftUI-native rect selector overlay
- Merge mic + system audio + video into a single MP4 via AVAssetWriter
- Show a proper preview while recording

Cost: ~200 lines of SCStream plumbing + AVAssetWriter setup. Low priority because macOS's native toolbar is already very good.

### Notes: richer block editor

Current preview splits body into `[text, image]` blocks. Natural extensions:

- Code blocks with syntax highlighting (Swift-syntax-highlighter or a simple regex tokeniser)
- Tables (Markdown pipes → SwiftUI `Grid`)
- Task lists (`- [ ]` checkboxes that toggle from the preview pane)
- Outgoing link preview cards
- Embeds: YouTube thumbnail, Tweet, etc. — probably scope creep

### Automation: AI tool-use

Right now slash commands (`/screenshots`, `/trash`) fire automations deterministically. True tool-use would let Claude / OpenAI / a CLI decide:

- "Can you clean up my Downloads?" → model picks `sortDL`, runs it, summarises result back in chat
- Requires a tool-calling contract per provider (Claude `tool_use`, OpenAI `function_call`, CLI structured output)
- Approval banner already exists — reuse it for AI-initiated destructive actions

### Shortcuts: groups / categories

Current grid is flat. Adding collapsible sections would help power-users with 30+ shortcuts:

- "Work", "Personal", "Utilities" — user-defined
- Drag between groups
- Each group gets its own `⌘<digit>` sequence? Too cute, skip.

### Clipboard: rich content

Currently only plain text is captured. Could extend to:

- Images (store in `clipboard-images/` with dedup like notes)
- File URLs (paste-as-link behaviour)
- Formatted text (RTF / HTML preservation)

### Stats / insights

Combined view of:

- Pomodoro streak + focus minutes over 30 days
- Automation run frequency
- Clipboard capture rate
- AI messages per day

Could live in the System tab or a new **Insights** tab (⌘0?).

## Already considered + rejected / deferred

### In-app toast overlays

Built in 1.1.0, **removed** in 1.2.0 at user's request. All event feedback now lands on the menu bar icon instead. Don't re-introduce toasts without a conscious product decision.

### Launch at login

Already implemented via `SMAppService.mainApp` in Settings → General → "Launch at login". Not expanding.

### Custom accent color

`SettingsStoreData.accentColorHex` exists and persists but isn't wired into any view. Low-impact; skip unless someone asks.

### Ollama provider selection in-app

Ollama is already detected as a CLI provider. Users set the model via the Ollama setting (defaults `llama3.2`). Exposing a model picker in NeuraBar would require listing `ollama list` output — doable but niche.

### Window selection for screen recording

Attempted with `screencapture -v -w` — macOS rejects the combination. A proper ScreenCaptureKit implementation is tracked under "Near-term candidates" above. The current hand-off to macOS Screenshot.app covers this use case.

## Non-goals

- **No sandboxing.** Sandboxed menu-bar apps can't run subprocesses (`screencapture`, CLI AI tools), can't read `~/Library/CloudStorage/*`, and can't post system-wide hotkeys. Hard blockers for NeuraBar's value prop.
- **No team / multi-user features.** Single-user productivity tool.
- **No Windows / Linux port.** AppKit-specific throughout.
- **No server backend.** All data local (or in the user's own cloud drive).
- **No telemetry.** Hard rule. If it ever becomes necessary, it's opt-in, locally readable, and never phones home by default.
