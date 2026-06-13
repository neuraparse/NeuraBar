# Testing

292 XCTest cases as of v1.3.0, ~6 s wall clock. All should pass on every commit.

## Running

Full Xcode (not just Command Line Tools — CLT doesn't ship XCTest):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

One-off: `sudo xcode-select -s /Applications/Xcode.app` then plain `swift test` works afterwards.

## Isolation: `NBTestCase`

Tests that hit any `Persistence`-backed store must inherit from `NBTestCase` (in `Tests/NeuraBarTests/TestSupport.swift`):

```swift
class NBTestCase: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeuraBarTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir
        Persistence.overrideDir = dir
    }

    override func tearDown() {
        Persistence.overrideDir = nil
        if let dir = tempDir { try? FileManager.default.removeItem(at: dir) }
        super.tearDown()
    }
}
```

This redirects `Persistence.supportDir` to a unique temp directory per test, preventing pollution of `~/Library/Application Support/NeuraBar/` and giving every test a fresh filesystem.

## Suites

| Suite | File | Count | Coverage |
|---|---|---|---|
| `LocalizationTests` | `LocalizationTests.swift` | 8 | EN/TR lookup, format args, auto-resolve, publish on change, every key has English translation |
| `SettingsStoreTests` | `SettingsStoreTests.swift` | 5 | Defaults, Codable round-trip, tolerant decode from v1 settings.json + `{}` |
| `TodoStoreTests` | `TodoStoreTests.swift` | 18 | CRUD, priority sort, due-date groups, tag extraction, filter, progress, tolerant decode |
| `ClipboardManagerTests` | `ClipboardManagerTests.swift` | 6 | Copy-to-top, pin toggle, clear-keeps-pinned, persistence round-trip |
| `NoteStoreTests` + `NoteItemTests` + `NoteEditorHelperTests` + `NotesAdaptiveLayoutTests` | `NoteStoreTests.swift` | 26 | Sort, filter, grouping, tolerant decode, word/char/reading-time counts, tag extraction, append helpers |
| `NoteAttachmentsTests` | `NoteAttachmentsTests.swift` | 13 | SHA-256 dedup, resolve bare/absolute/missing, extract tokens, orphan pruning, body parser blocks |
| `ShortcutStoreTests` | `ShortcutStoreTests.swift` | 19 | CRUD, pin, launch counter, sort, filter by kind/search, systemIcon fetch, legacy decode, bulk-add, color persistence |
| `AutomationCatalogTests` + `AutomationCounterParsingTests` + `AutomationStoreTests` | `AutomationTests.swift` | 14 | Catalog count (12), unique IDs, per-category defs, parseCounter/stripCounters edge cases, history persistence |
| `AIProviderTests` | `AIProviderTests.swift` | 7 | `which` for ls and phantom binary, detect shape, API-provider presence gated by keys, ID-based equality |
| `AIDetectorCacheTests` | `AIDetectorCacheTests.swift` | 5 | Cache stability for hits and nils, 50-lookup perf budget, `invalidateWhichCache` re-probes, `useCache: false` opt-out |
| `AIConversationTests` | `AIConversationTests.swift` | 21 | CRUD, append auto-creates + auto-titles, updateMessage transform, sort pinned-first, filter, duplicate copies, persistence round-trip, ChatMessage + AIConversation tolerant decode |
| `AssistantBehaviorTests` | `AssistantBehaviorTests.swift` | 12 | Streaming accumulation, error-path cleanup contract, switching conversations swaps messages, provider stamping, pin ordering, filter, auto-title boundaries |
| `TabTests` | `MiscTests.swift` | 5 | ⌘1–⌘9 range, unique keys, distinct title keys, count = 9, Record tab present |
| `PomodoroTests` | `MiscTests.swift` | 14 | State machine, time string, progress, mode durations, skip/extend semantics, stats (sessionsToday / focusMinutes / streak), config + session persistence |
| `PersistenceTests` | `MiscTests.swift` | 4 | Override dir takes effect, save/load round-trip, nil on missing + corrupt |
| `GlobalHotkeyTests` | `GlobalHotkeyTests.swift` | 8 | Default binding ⌘⌥N, humanReadable formatter, combine all modifiers, F-key, Equatable, singleton, unregister-without-register, F15 integration |
| `RecordingTests` | `RecordingTests.swift` | 13 | Directory auto-create, filename shape per kind, filename uniqueness per second, formatDuration edge cases, formatBytes, initial state, phantom-file filtering, delete + clearAll |
| `RecordingSourceMetadataTests` + `ScreencaptureArgumentsTests` | `RecordingSourceTests.swift` | 9 | Full screen default args, mic/cursor flag toggles, area → `-i`, systemPicker stays clean, output path always last, icon + title key presence, distinct title keys |
| `SystemAlertTests` | `SystemAlertTests.swift` | 14 | Healthy → OK + no reasons, CPU/memory/disk/battery thresholds, disabled metric skip, mem-total-0 defensive, battery-while-charging silence, escalation (critical beats warning), config persist, tolerant decode |
| `PermissionsServiceTests` + `PermissionsStoreActionTests` + `RecordingGuardTests` | `PermissionsTests.swift` | 14 | URL builders, state → next-action mapping, restart wins, startScreen returns false when denied, system picker + area bypass guards |
| `NotificationServiceTests` + `RecordingOptionsTests` | `NotificationServiceTests.swift` | 6 | Bundle guard makes isAvailable false under XCTest, post is no-op, options defaults + persist + tolerant decode, microphone enumeration |
| `MenuBarStatusTests` | `MenuBarStatusTests.swift` | 7 | Flash sets + replaces + auto-clears, clear cancels pending, each event has icon + duration in budget |
| `MenuBarIconPrecedenceTests` | `MenuBarIconPrecedenceTests.swift` | 6 | Pomodoro running flag flips, reset returns to idle, phases are distinct, precedence contract |
| `RecordFlowTests` | `RecordFlowTests.swift` | 12 | Idle state, start/stop symmetry, stop-when-idle no-ops, system picker + area hand off, already-recording returns false, options persist, formatDuration ranges, args builder pure, singletons stable |
| `DataLocationTests` | `DataLocationTests.swift` | 11 | Resolver fallbacks, custom mode path append, availability probes, migrate JSONs, `location.json` skipped, idempotent, empty decode, bootstrap round-trip, labels + icons |

## Guarding rules

- **Never ship with failing tests.** The suite is fast enough to run on every change.
- **Never introduce warnings.** Swift 6 concurrency warnings are non-negotiable.
- **New Loc keys must be added to `LocalizationTests.testEveryLocKeyHasEnglishTranslation`'s allCases list.** Otherwise the test silently passes but the UI renders raw key names.
- **New Codable fields must come with a tolerant decode test.** One for the legacy JSON missing the field, one for `{}`.
- **Permission-touching code paths must be guarded with `Bundle.main.bundlePath.hasSuffix(".app")`.** Tests run inside the xctest binary and macOS throws `NSInternalInconsistencyException` for UserNotifications / some AVFoundation calls without a real .app bundle.

## Performance budgets

Locked by tests:

- `AIDetectorCacheTests.testCachedNilSurvives` — 50 cached `which` lookups in < 100 ms.
- `AIDetectorCacheTests.testDetectIsFastOnSecondCall` — 5 cached `detect` calls in < 200 ms.
- `MenuBarStatusTests.testDefaultDurationIsReasonable` — every event duration ≤ 3 s.
