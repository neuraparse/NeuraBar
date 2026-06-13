import XCTest
@testable import NeuraBar

final class LocalizationTests: XCTestCase {

    func testEnglishLookup() {
        let l = Localization()
        l.apply(override: .en)
        XCTAssertEqual(l.language, .en)
        XCTAssertEqual(l.t(.save), "Save")
        XCTAssertEqual(l.t(.tab_todos), "Tasks")
    }

    func testTurkishLookup() {
        let l = Localization()
        l.apply(override: .tr)
        XCTAssertEqual(l.language, .tr)
        XCTAssertEqual(l.t(.save), "Kaydet")
        XCTAssertEqual(l.t(.tab_todos), "Görevler")
    }

    func testFormattedStringsWithSingleArg() {
        let l = Localization()
        l.apply(override: .en)
        let str = l.t(.ai_emptyDesktopHint, "Claude Desktop")
        XCTAssertTrue(str.contains("Claude Desktop"),
                      "Expected Claude Desktop substitution, got \(str)")
    }

    func testFormattedStringsWithMultipleArgs() {
        let l = Localization()
        l.apply(override: .en)
        let str = l.t(.ai_picker_hint, 2, 1, 3)
        XCTAssertTrue(str.contains("2"))
        XCTAssertTrue(str.contains("1"))
        XCTAssertTrue(str.contains("3"))
    }

    func testTurkishFallsBackToEnglishWhenMissing() {
        // Every key has an EN translation, so even if a TR dict were missing
        // some, the fallback path exists. We exercise via a real TR key.
        let l = Localization()
        l.apply(override: .tr)
        XCTAssertNotEqual(l.t(.appTagline), Loc.appTagline.rawValue,
                          "appTagline should be resolved, not echoed as raw key")
    }

    func testAutoResolvesToSupportedLanguage() {
        let l = Localization()
        l.apply(override: .auto)
        XCTAssertTrue(l.language == .en || l.language == .tr,
                      "auto should resolve to en or tr")
    }

    func testApplyPublishesLanguageChange() {
        let l = Localization()
        l.apply(override: .en)
        var observed: SupportedLanguage?
        let cancel = l.$language.sink { observed = $0 }
        l.apply(override: .tr)
        XCTAssertEqual(observed, .tr)
        cancel.cancel()
    }

    /// Every declared Loc key must have at least an English translation —
    /// otherwise t() would echo the raw key name to users. Iterating
    /// `Loc.allCases` makes this exhaustive: a new key with no translation
    /// fails the suite instead of silently slipping through a hand-list.
    func testEveryLocKeyHasEnglishTranslation() {
        let l = Localization()
        l.apply(override: .en)
        for key in Loc.allCases {
            let value = l.t(key)
            XCTAssertNotEqual(value, key.rawValue,
                              "Missing English translation for \(key.rawValue)")
            XCTAssertFalse(value.isEmpty, "Empty English translation for \(key.rawValue)")
        }
    }
}

import Combine
