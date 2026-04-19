import XCTest
@testable import NeuraBar

/// NotificationService short-circuits every call when running outside a real
/// .app bundle, so `swift test` never crashes with
/// NSInternalInconsistencyException from UserNotifications.
final class NotificationServiceTests: XCTestCase {

    func testIsAvailableReturnsFalseUnderXCTest() {
        XCTAssertFalse(NotificationService.isAvailable,
                       "Without a real .app bundle, notifications must no-op")
    }

    func testPostDoesNotCrashWithoutBundle() {
        NotificationService.post(title: "x", body: "y")
        NotificationService.post(title: "x", body: "y", subtitle: "z")
        NotificationService.requestAuthorizationIfNeeded()
    }
}

final class RecordingOptionsTests: NBTestCase {

    func testOptionsDefaults() {
        let s = RecordingStore()
        XCTAssertTrue(s.options.includeMicrophone)
        XCTAssertTrue(s.options.captureCursor)
        XCTAssertTrue(s.options.postNotification)
    }

    func testOptionsPersistAcrossInstances() {
        let s1 = RecordingStore()
        s1.options.includeMicrophone = false
        s1.options.captureCursor = false
        s1.options.postNotification = false

        let s2 = RecordingStore()
        XCTAssertFalse(s2.options.includeMicrophone)
        XCTAssertFalse(s2.options.captureCursor)
        XCTAssertFalse(s2.options.postNotification)
    }

    func testTolerantDecodeOfEmptyOptions() throws {
        let data = "{}".data(using: .utf8)!
        let opts = try JSONDecoder().decode(RecordingOptions.self, from: data)
        XCTAssertTrue(opts.includeMicrophone)
        XCTAssertTrue(opts.captureCursor)
    }

    func testMicrophoneEnumerationDoesNotCrash() {
        let mics = RecordingStore.availableMicrophones
        XCTAssertGreaterThanOrEqual(mics.count, 0)
        for entry in mics {
            XCTAssertFalse(entry.id.isEmpty)
            XCTAssertFalse(entry.name.isEmpty)
        }
    }
}
