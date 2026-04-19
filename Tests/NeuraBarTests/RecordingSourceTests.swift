import XCTest
@testable import NeuraBar

/// The `screencapture` argument list is the actual contract between NeuraBar
/// and macOS for screen recording. These tests pin the flag plumbing so a
/// change that silently drops `-g` (no audio) or `-C` (no cursor) trips up.
final class ScreencaptureArgumentsTests: XCTestCase {

    private let defaultPath = "/tmp/neurabar-test.mov"

    // MARK: - Defaults (mic + cursor on)

    func testFullScreenDefaultArgs() {
        var opts = RecordingOptions()
        opts.includeMicrophone = true
        opts.captureCursor = true
        let args = RecordingStore.screencaptureArguments(
            source: .fullScreen,
            outputPath: defaultPath,
            options: opts
        )
        XCTAssertTrue(args.contains("-v"))
        XCTAssertTrue(args.contains("-x"))
        XCTAssertTrue(args.contains("-C"))
        XCTAssertTrue(args.contains("-g"))
        XCTAssertFalse(args.contains("-i"),
                       "Full-screen mode should not request interactive selection")
        XCTAssertEqual(args.last, defaultPath,
                       "Output path must be the final argument to screencapture")
    }

    // MARK: - Options

    func testMicrophoneOptionDropsDashG() {
        var opts = RecordingOptions()
        opts.includeMicrophone = false
        opts.captureCursor = true
        let args = RecordingStore.screencaptureArguments(
            source: .fullScreen, outputPath: defaultPath, options: opts
        )
        XCTAssertFalse(args.contains("-g"))
    }

    func testCursorOptionDropsDashC() {
        var opts = RecordingOptions()
        opts.captureCursor = false
        opts.includeMicrophone = true
        let args = RecordingStore.screencaptureArguments(
            source: .fullScreen, outputPath: defaultPath, options: opts
        )
        XCTAssertFalse(args.contains("-C"))
        XCTAssertTrue(args.contains("-g"))
    }

    // MARK: - Source modes

    func testAreaSourceAddsInteractiveFlag() {
        let args = RecordingStore.screencaptureArguments(
            source: .area, outputPath: defaultPath, options: RecordingOptions()
        )
        XCTAssertTrue(args.contains("-i"),
                      "Area mode requires -i so macOS prompts for a rect")
    }

    func testSystemPickerDoesNotAddCaptureFlags() {
        // Even though we still build an args list for symmetry, the caller
        // never actually launches screencapture in systemPicker mode. But
        // we shouldn't accidentally pollute the list with -i or similar.
        let args = RecordingStore.screencaptureArguments(
            source: .systemPicker, outputPath: defaultPath, options: RecordingOptions()
        )
        XCTAssertFalse(args.contains("-i"))
        XCTAssertEqual(args.last, defaultPath)
    }

    // MARK: - Output path is always last

    func testOutputPathIsFinalArgRegardlessOfOptions() {
        var opts = RecordingOptions()
        opts.includeMicrophone = false
        opts.captureCursor = false
        let args = RecordingStore.screencaptureArguments(
            source: .area, outputPath: "/tmp/out.mov", options: opts
        )
        XCTAssertEqual(args.last, "/tmp/out.mov")
    }
}

/// The RecordingSource enum is pure metadata — but the UI relies on every
/// case supplying an icon + title/subtitle key.
final class RecordingSourceMetadataTests: XCTestCase {

    func testEveryCaseHasAnIcon() {
        for source in [RecordingSource.fullScreen, .area, .systemPicker] {
            XCTAssertFalse(source.icon.isEmpty,
                           "Missing SF Symbol for \(source.rawValue)")
        }
    }

    func testEveryCaseHasTitleAndSubtitleKeys() {
        let l = Localization()
        l.apply(override: .en)
        for source in [RecordingSource.fullScreen, .area, .systemPicker] {
            XCTAssertNotEqual(l.t(source.titleKey), source.titleKey.rawValue,
                              "\(source.rawValue) title falls through to raw key")
            XCTAssertNotEqual(l.t(source.subtitleKey), source.subtitleKey.rawValue,
                              "\(source.rawValue) subtitle falls through to raw key")
        }
    }

    func testTitleKeysAreDistinct() {
        let keys: [Loc] = [
            RecordingSource.fullScreen.titleKey,
            RecordingSource.area.titleKey,
            RecordingSource.systemPicker.titleKey
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
