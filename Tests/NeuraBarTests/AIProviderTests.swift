import XCTest
@testable import NeuraBar

final class AIProviderTests: XCTestCase {

    func testWhichReturnsNilForNonexistentBinary() {
        let path = AIDetector.which("definitely-not-a-real-command-xyz-\(UUID())")
        XCTAssertNil(path)
    }

    func testWhichFindsCommonSystemTool() {
        // `ls` lives in /bin — should always be found on macOS.
        let path = AIDetector.which("ls")
        XCTAssertNotNil(path, "Expected to find /bin/ls or equivalent")
    }

    func testDetectReturnsArrayWithEmptySettings() {
        let settings = SettingsStoreData()
        let providers = AIDetector.detect(settings: settings)
        // Result shape check — detect() must never crash and must return an
        // Array. The actual providers depend on the host system.
        XCTAssertNotNil(providers)
        // Every returned provider should have a non-empty id and name.
        for p in providers {
            XCTAssertFalse(p.id.isEmpty)
            XCTAssertFalse(p.name.isEmpty)
        }
    }

    func testDetectIncludesClaudeAPIWhenKeyPresent() {
        var settings = SettingsStoreData()
        settings.claudeAPIKey = "sk-ant-fake"
        let providers = AIDetector.detect(settings: settings)
        XCTAssertTrue(providers.contains { $0.id == "claude-api" },
                      "With a Claude key, Claude API provider must appear")
    }

    func testDetectIncludesOpenAIAPIWhenKeyPresent() {
        var settings = SettingsStoreData()
        settings.openaiAPIKey = "sk-fake"
        let providers = AIDetector.detect(settings: settings)
        XCTAssertTrue(providers.contains { $0.id == "openai-api" })
    }

    func testDetectOmitsAPIsWhenKeysEmpty() {
        let settings = SettingsStoreData()
        let providers = AIDetector.detect(settings: settings)
        XCTAssertFalse(providers.contains { $0.id == "claude-api" })
        XCTAssertFalse(providers.contains { $0.id == "openai-api" })
    }

    func testProviderEqualityIsIDBased() {
        let a = AIProvider(id: "x", name: "A", subtitle: "", icon: "", kind: .api)
        let b = AIProvider(id: "x", name: "B-different-name", subtitle: "", icon: "", kind: .cli)
        let c = AIProvider(id: "y", name: "A", subtitle: "", icon: "", kind: .api)
        XCTAssertEqual(a, b, "Providers with same id are equal regardless of other fields")
        XCTAssertNotEqual(a, c)
    }
}
