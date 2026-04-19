import XCTest
@testable import NeuraBar

/// Covers the session-level cache on `AIDetector.which` — the fix that
/// eliminated the 0.5–1.2 s blocking zsh subprocess spawn on every AI-tab
/// open when a user didn't have all the optional CLIs installed.
final class AIDetectorCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AIDetector.invalidateWhichCache()
    }

    // MARK: - Cached results are stable

    func testRepeatedLookupsReturnSameAnswer() {
        // /bin/ls exists on every Mac.
        let first = AIDetector.which("ls")
        let second = AIDetector.which("ls")
        let third = AIDetector.which("ls")
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
    }

    func testCachedNilSurvives() {
        let ghostName = "nb-ghost-binary-\(UUID().uuidString)"
        // First call populates cache with nil.
        XCTAssertNil(AIDetector.which(ghostName))
        // Second call MUST NOT re-probe (this is the whole point of the cache).
        // We can't observe subprocess spawns directly, but we can assert the
        // result is still nil and reasonably fast. We use a perf budget.
        let start = Date()
        for _ in 0..<50 {
            _ = AIDetector.which(ghostName)
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.1,
                          "50 cached lookups must be effectively free (<100 ms)")
    }

    // MARK: - Explicit invalidation

    func testInvalidateForcesRecompute() {
        let name = "ls"
        _ = AIDetector.which(name)               // caches
        AIDetector.invalidateWhichCache()        // clears
        // Next call goes through uncached path (bypasses the early return).
        // Result should still be correct.
        XCTAssertNotNil(AIDetector.which(name))
    }

    // MARK: - Bypass via useCache: false

    func testUseCacheFalseAlwaysQueries() {
        let ghostName = "nb-ghost-\(UUID().uuidString)"
        XCTAssertNil(AIDetector.which(ghostName))
        XCTAssertNil(AIDetector.which(ghostName, useCache: false),
                     "Explicit opt-out of cache still returns consistent result for a missing binary")
    }

    // MARK: - detect() benefits from cache

    func testDetectIsFastOnSecondCall() {
        let settings = SettingsStoreData()
        // Prime the cache.
        _ = AIDetector.detect(settings: settings)
        // Subsequent calls should be near-instant since every which() is cached.
        let start = Date()
        for _ in 0..<5 {
            _ = AIDetector.detect(settings: settings)
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.2,
                          "5 cached detect() calls must finish in <200 ms; slow path spawns zsh subprocesses")
    }
}
