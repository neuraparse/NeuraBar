import Foundation
import XCTest
@testable import NeuraBar

/// Every test case inherits from this to get an isolated temp support dir.
/// Prevents tests from touching the real ~/Library/Application Support/NeuraBar.
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
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }
}
