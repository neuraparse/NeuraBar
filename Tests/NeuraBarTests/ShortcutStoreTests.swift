import XCTest
import AppKit
@testable import NeuraBar

final class ShortcutStoreTests: NBTestCase {

    // MARK: - Seed + CRUD

    func testSeedsDefaultsWhenMissing() {
        let s = ShortcutStore()
        XCTAssertFalse(s.items.isEmpty, "ShortcutStore should ship with defaults")
        XCTAssertTrue(s.items.contains(where: { $0.name == "Terminal" }))
    }

    func testAddAppendsToEnd() {
        let s = ShortcutStore()
        s.items = []
        s.add(ShortcutItem(name: "X", path: "/x", icon: "star", kind: .app))
        XCTAssertEqual(s.items.count, 1)
        XCTAssertEqual(s.items.last?.name, "X")
    }

    func testRemove() {
        let s = ShortcutStore()
        s.items = [
            ShortcutItem(name: "alpha", path: "/a", icon: "star", kind: .app),
            ShortcutItem(name: "beta", path: "/b", icon: "star", kind: .app)
        ]
        let alpha = s.items[0]
        s.remove(alpha)
        XCTAssertEqual(s.items.count, 1)
        XCTAssertEqual(s.items.first?.name, "beta")
    }

    // MARK: - Pin + launch tracking

    func testTogglePin() {
        let s = ShortcutStore()
        s.items = [ShortcutItem(name: "a", path: "/a", icon: "x", kind: .app)]
        XCTAssertFalse(s.items[0].pinned)
        s.togglePin(s.items[0])
        XCTAssertTrue(s.items[0].pinned)
        s.togglePin(s.items[0])
        XCTAssertFalse(s.items[0].pinned)
    }

    func testLaunchIncrementsCounterAndStamps() {
        let s = ShortcutStore()
        // Use a URL kind so NSWorkspace tries to open a safe no-op.
        s.items = [ShortcutItem(name: "harmless", path: "about:blank", icon: "link", kind: .url)]
        XCTAssertEqual(s.items[0].launchCount, 0)
        XCTAssertNil(s.items[0].lastLaunched)
        s.launch(s.items[0])
        XCTAssertEqual(s.items[0].launchCount, 1)
        XCTAssertNotNil(s.items[0].lastLaunched)
    }

    // MARK: - Sort

    func testSortPinnedFirstThenFrequencyThenRecency() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 500)
        let items = [
            ShortcutItem(name: "cold", path: "/a", icon: "x", kind: .app),
            ShortcutItem(name: "hot", path: "/b", icon: "x", kind: .app,
                         launchCount: 5, lastLaunched: older),
            ShortcutItem(name: "recent", path: "/c", icon: "x", kind: .app,
                         launchCount: 1, lastLaunched: newer),
            ShortcutItem(name: "pinned-cold", path: "/d", icon: "x", kind: .app,
                         pinned: true)
        ]
        let sorted = ShortcutStore.sort(items)
        XCTAssertEqual(sorted[0].name, "pinned-cold")
        XCTAssertEqual(sorted[1].name, "hot")
        XCTAssertEqual(sorted[2].name, "recent")
        XCTAssertEqual(sorted[3].name, "cold")
    }

    // MARK: - Filter

    func testFilterByKind() {
        let s = ShortcutStore()
        s.items = [
            ShortcutItem(name: "safari", path: "/Applications/Safari.app", icon: "safari", kind: .app),
            ShortcutItem(name: "downloads", path: "/Users/x/Downloads", icon: "folder", kind: .folder),
            ShortcutItem(name: "github", path: "https://github.com", icon: "link", kind: .url)
        ]
        XCTAssertEqual(s.filter(query: "", kind: .all).count, 3)
        XCTAssertEqual(s.filter(query: "", kind: .app).count, 1)
        XCTAssertEqual(s.filter(query: "", kind: .folder).count, 1)
        XCTAssertEqual(s.filter(query: "", kind: .url).count, 1)
    }

    func testFilterBySearchMatchesNameOrPath() {
        let s = ShortcutStore()
        s.items = [
            ShortcutItem(name: "Work Projects", path: "/Users/x/Projects", icon: "folder", kind: .folder),
            ShortcutItem(name: "Safari", path: "/Applications/Safari.app", icon: "safari", kind: .app)
        ]
        XCTAssertEqual(s.filter(query: "work", kind: .all).count, 1)
        XCTAssertEqual(s.filter(query: "projects", kind: .all).count, 1)
        XCTAssertEqual(s.filter(query: "applications", kind: .all).count, 1,
                       "Path match should also count")
        XCTAssertEqual(s.filter(query: "xyz", kind: .all).count, 0)
    }

    func testFilterCombinesKindAndQuery() {
        let s = ShortcutStore()
        s.items = [
            ShortcutItem(name: "Safari", path: "/Applications/Safari.app", icon: "safari", kind: .app),
            ShortcutItem(name: "Safari bookmark", path: "https://safari.com", icon: "link", kind: .url)
        ]
        let hits = s.filter(query: "safari", kind: .app)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.kind, .app)
    }

    // MARK: - Icon fetching

    func testSystemIconReturnsNilForNonexistentPath() {
        let item = ShortcutItem(name: "ghost", path: "/tmp/nope-\(UUID()).app",
                                icon: "x", kind: .app)
        XCTAssertNil(ShortcutStore.systemIcon(for: item))
    }

    func testSystemIconReturnsImageForRealFolder() {
        // Every Mac has /tmp; it's a folder we can point at safely.
        let item = ShortcutItem(name: "tmp", path: "/tmp", icon: "folder", kind: .folder)
        let img = ShortcutStore.systemIcon(for: item)
        XCTAssertNotNil(img)
    }

    func testSystemIconReturnsNilForURLKind() {
        let item = ShortcutItem(name: "github", path: "https://github.com",
                                icon: "link", kind: .url)
        XCTAssertNil(ShortcutStore.systemIcon(for: item))
    }

    // MARK: - Tolerant decode

    func testDecodesLegacyShortcutsJSON() throws {
        let legacy = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Terminal",
            "path": "/System/Applications/Utilities/Terminal.app",
            "icon": "terminal",
            "kind": "app"
          }
        ]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([ShortcutItem].self, from: legacy)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "Terminal")
        XCTAssertFalse(decoded[0].pinned, "Missing pinned defaults to false")
        XCTAssertEqual(decoded[0].launchCount, 0)
        XCTAssertNil(decoded[0].lastLaunched)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        let s1 = ShortcutStore()
        s1.items = [
            ShortcutItem(name: "persistent", path: "/p", icon: "star", kind: .url,
                         pinned: true, launchCount: 7)
        ]
        let s2 = ShortcutStore()
        XCTAssertEqual(s2.items.count, 1)
        XCTAssertEqual(s2.items.first?.name, "persistent")
        XCTAssertTrue(s2.items.first?.pinned ?? false)
        XCTAssertEqual(s2.items.first?.launchCount, 7)
    }
}
