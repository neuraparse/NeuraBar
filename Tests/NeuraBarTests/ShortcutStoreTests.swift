import XCTest
@testable import NeuraBar

final class ShortcutStoreTests: NBTestCase {

    func testSeedsDefaultsWhenMissing() {
        let s = ShortcutStore()
        XCTAssertFalse(s.items.isEmpty, "ShortcutStore should ship with defaults")
        XCTAssertTrue(s.items.contains(where: { $0.name == "Terminal" }))
    }

    func testAdd() {
        let s = ShortcutStore()
        let before = s.items.count
        s.add(ShortcutItem(name: "My App", path: "/Applications/Safari.app",
                           icon: "safari", kind: .app))
        XCTAssertEqual(s.items.count, before + 1)
        XCTAssertEqual(s.items.last?.name, "My App")
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

    func testPersistenceRoundTrip() {
        let s1 = ShortcutStore()
        s1.items = [
            ShortcutItem(name: "persistent", path: "/p", icon: "star", kind: .url)
        ]
        let s2 = ShortcutStore()
        XCTAssertEqual(s2.items.count, 1)
        XCTAssertEqual(s2.items.first?.name, "persistent")
        XCTAssertEqual(s2.items.first?.kind, .url)
    }
}
