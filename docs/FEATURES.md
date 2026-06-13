# Features

Complete inventory of everything NeuraBar does as of v1.3.0.

## Tabs

### ✓ Tasks (⌘1)

- Add via text field; prefix `!` or `!!` for high priority
- Priority (low / normal / high) with coloured left stripe + sort weight
- Due dates with quick actions: Today / Tomorrow / Next Week / Clear
- `#hashtag` tags extracted live from the title, Unicode-aware
- Search bar + tag chip filter
- Time-grouped display: **Overdue → Today → Tomorrow → This week → Later → Someday → Completed**
- Progress ring in the header showing X of Y done (numeric morph)
- Hover actions: priority menu, due-date picker, delete
- Context menu: mark done, priority submenu, delete
- Keyboard: `⌘⇧N` new, `⌘⇧Delete` clear done

### ⏱ Focus / Pomodoro (⌘2)

- 5 preset modes: **Classic** (25/5/15) · **Extended** (50/10/30) · **Short** (15/3/10) · **Deep** (90/20/45) · **Custom**
- Custom sheet with steppers for focus / short break / long break + daily goal
- Contextual actions while running: **Skip** (advance phase) · **+5 min** (extend, max +60 per call)
- Daily stats: 🔥 streak · ✓ sessions today · ⏱ focus minutes · 🎯 goal ring
- Phase-aware timer dial gradient (focus purple · short break green · long break teal)
- Numeric countdown with `contentTransition(.numericText(countsDown: true))`
- Big timer (240×240) in pop-out mode; compact (180×180) in popover
- Auto-start breaks / next focus toggles (persisted)
- macOS notifications on phase completion (guarded by real-app-bundle check)
- Session history in `pomodoro_sessions.json`, last 500 retained
- **Menu bar icon** swaps to a phase-tinted timer glyph while running

### ▦ Shortcuts (⌘3)

- Adaptive grid (`LazyVGrid` minimum 86 px cell)
- **Real app icons** via `NSWorkspace.shared.icon(forFile:)` for `.app` and folder shortcuts
- SF Symbol fallback with purple→blue gradient for URLs and commands
- Pin favourites to the top (orange pin badge + border)
- Launch counter + last-launched timestamp
- Sort: **pinned → most-used → most-recently-used → original order**
- Per-shortcut color tag (9 colors) — tints the tile background and border
- **Drag-reorder** any tile via SwiftUI's `.draggable` / `.dropDestination(for: String.self)`
- **Drop zone** from Finder — drag a `.app` or folder anywhere onto the tab to auto-add
- **Multi-import** button opens `NSOpenPanel` rooted at `/Applications` with multi-select
- Edit via double-click or hover pencil → reuses `AddShortcutSheet` in edit mode
- `⌘1` – `⌘9` quick launch for the first nine visible tiles
- Context menu: Pin/Unpin, Edit, Color submenu, launch count, Copy path, Remove

### ✨ Automate (⌘4)

12 automations across 3 categories:

| Category | Actions |
|---|---|
| **Files** | Sort screenshots · Sort Downloads by type · HEIC → JPG · Largest files report · Archive old downloads |
| **Cleanup** | Installer sweep (.dmg/.pkg/.msi) · Purge .DS_Store · Empty Trash · Clean Xcode DerivedData |
| **System** | Toggle hidden files · Lock screen · Sleep display |

- Each automation returns an `AutomationResult`: summary, stats (Moved / Deleted / Size / Converted / Duration), details log, status (succeeded / failed)
- **Destructive actions** (trash, dsstore, derived, lock, sleep) require explicit **Approve** — orange banner with shield icon
- Structured run history (50 runs) in `automation_history.json`
- Expandable run cards show stats + detail log
- **Menu bar icon** flashes green check on success, red octagon on failure

### ⎘ Clipboard (⌘5)

- Polls `NSPasteboard.general` at 1 Hz; captures text up to 100 k chars
- **Persistent** across restarts in `clipboard.json` (max 200 items, pin-aware trim)
- Pin favourites with `pin.fill` indicator
- Dedup: re-copying an existing item moves it to the top
- Search across all items
- Context menu: Pin/Unpin, Delete
- **Menu bar icon** flashes blue `doc.on.clipboard` on capture and on manual copy

### ✎ Notes (⌘6)

Notion-style:

- **Drag-and-drop images** onto the editor (PNG, JPG, HEIC, GIF, WebP, TIFF)
- **Paste image** button handles TIFF/PNG/URL from clipboard
- Content-addressed storage in `notes-images/<sha256>.<ext>` — identical bytes dedupe
- Markdown edit mode (plain `TextEditor`), preview mode renders text + images inline
- `⌘/` toggles edit ↔ preview
- Toolbar: Bold (`⌘B`) · Italic (`⌘I`) · Inline code · Bulleted list · Checklist · Heading · Timestamp (`⌘;`) · Copy-all
- Word / character / reading-time counters with numeric transitions
- `#tag` extraction (Unicode, case-insensitive dedup)
- Time-grouped sidebar: **Pinned → Today → Yesterday → This week → Older**
- Color stripes per note (9 colors)
- Pin, duplicate, delete (context menu + keyboard)
- **Adaptive layout**: single-pane navigation in popover (< 520 px), split view in big window

### ● Record (⌘7)

- **Audio** via `AVAudioRecorder` — 44.1 kHz mono AAC `.m4a`
- **Screen** via `screencapture -v` with options:
  - `-C` capture cursor
  - `-g` include microphone + system audio track
- Source picker sheet with 3 iconified tiles: **Full Screen** · **Area** · **macOS Screenshot toolbar**
- Area and Screenshot toolbar hand off to macOS's own recorder (supports window / area that `screencapture -i -v` can't)
- **Permissions banners** at the top of the tab — pulsing red for denied, orange for not-asked, blue for just-granted-needs-restart, hidden for good
- **Before recording**: `WindowManager.hideAllWindows()` closes popover + pop-out so NeuraBar never appears in the video
- Live audio level meter (0–1 derived from `averagePower`)
- Pill-shaped Start/Stop buttons with phase pulse and duration counter
- Recordings saved to `~/Downloads/NeuraBar Recordings/` with deterministic filenames `audio-YYYY-MM-DD_HH-mm-ss.m4a` / `screen-…mov`
- Metadata persisted in `recordings.json`; orphaned files auto-filtered on load
- Row actions: reveal in Finder · delete · open on double-click
- Recording saved fires a **menu bar icon flash** (pink waveform) + optional OS notification

### ▤ System (⌘8)

- Live CPU / RAM / Disk / Battery readouts, 3 s polling
- Alert level (ok / warning / critical) with reason list
- **Threshold editor**: per-metric warn + crit sliders, per-metric enable toggle
- Pulsing status header (green when OK, orange warning, red critical)
- **Menu bar icon** swaps to a red warning triangle on critical, or shows an orange dot overlay on warning
- Critical transitions post an OS notification (once per transition, not per tick)
- All config persists in `system_alert_config.json`

### ⚡ AI (⌘9)

- **11 CLI providers** auto-detected: Claude Code, Codex, Aider, opencode, Gemini, Amp, Goose, Qwen Code, Plandex, Continue, Ollama
- **2 API providers**: Anthropic Claude, OpenAI (bring your own key in Settings)
- **4 desktop apps**: Claude Desktop, ChatGPT, Codex, ChatGPT Atlas — hand-off pattern (clipboard + open app)
- Provider bar with picker dropdown + live provider count
- Persistent conversation history (ChatGPT-style):
  - **Wide mode**: left sidebar with conversation list + New button
  - **Compact mode**: top bar with conversation title → tap for overlay picker
  - Auto-title from first user message (40-char cap)
  - Rename · Pin · Duplicate · Delete via context menu
  - Sort: pinned first, then most-recently-updated
- Slash commands (`/screenshots`, `/trash`, …) run automations from the chat
- Quick action chips above the input — context-aware suggestions based on the last user message
- Approval banner for destructive automations (orange shield)
- Rich progress indicator: `BrandPulse` + provider name + live elapsed seconds via `TimelineView`
- Streaming CLI chunks update the assistant bubble in real time (observed via `@EnvironmentObject`)
- `AIDetector.which` cached per session — first AI tab open is instant after the initial probe

## Cross-cutting

### Command palette (⌘K)

- Fuzzy search across: tabs, todos, notes, shortcuts, clipboard, quick actions
- Arrow keys navigate, Enter activates, Esc cancels
- Sectioned results with icons and section headers
- Glass-styled sheet, springs in / out

### Global hotkey (⌘⌥N)

- Carbon-based `RegisterEventHotKey` — **no Accessibility permission required**
- Toggles the pop-out window from anywhere
- Binding chosen to avoid collisions with Finder / Safari / Chrome / IDEs

### Data location (iCloud / Google Drive / custom)

- Settings → General → Data location card
- Auto-detects iCloud Drive desktop sync and Google Drive desktop client folders
- Custom folder picker for Dropbox / OneDrive / anywhere
- Migration copies all JSON + `notes-images/` on change
- Bootstrap file (`location.json`) always stays in Application Support

### Permissions

- Screen Recording via `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`
- Microphone via `AVCaptureDevice.authorizationStatus` / `requestAccess`
- Deep links to System Settings privacy panes
- One-click restart when macOS has cached old TCC state

### Menu bar icon states

| State | Rendering |
|---|---|
| Default | Template NeuraMark (adapts to light/dark) |
| System warning | NeuraMark + orange dot overlay |
| System critical | Red `exclamationmark.triangle.fill` with pulsing symbol effect |
| Pomodoro running | Phase-tinted `timer` symbol with variable-color pulse (purple/green/teal) |
| Event flash | Colored event glyph (~1.4 s, `symbolEffect(.bounce)`) |

### Localization

- English + Turkish, auto-detected from macOS language
- Override in Settings → General → Language
- Every `Loc` key has an English translation; test guards this
- `Localization.shared` is an `ObservableObject` so language changes re-render everything

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘⌥N` | Global: toggle NeuraBar window from anywhere |
| `⌘K` | Command palette |
| `⌘,` | Settings |
| `⌘1`–`⌘9` | Jump to tab |
| `⌘⇧N` | New task / note / AI conversation (tab-scoped) |
| `⌘D` | Duplicate active note |
| `⌘/` | Notes preview toggle |
| `⌘;` | Notes timestamp insert |
| `⌘B` / `⌘I` | Notes bold / italic markers |
| `⌘⇧Delete` | Todos: clear completed |
| `⌘Q` | Quit |
