import XCTest
@testable import NeuraBar

final class SettingsStoreTests: NBTestCase {

    func testDefaultsWhenNoFile() {
        let data = SettingsStoreData()
        XCTAssertEqual(data.claudeModel, "claude-sonnet-4-5")
        XCTAssertEqual(data.openaiModel, "gpt-4o-mini")
        XCTAssertEqual(data.ollamaModel, "llama3.2")
        XCTAssertEqual(data.language, .auto)
        XCTAssertEqual(data.claudeAPIKey, "")
    }

    func testCodableRoundTrip() throws {
        var original = SettingsStoreData()
        original.claudeAPIKey = "sk-ant-test"
        original.openaiAPIKey = "sk-test"
        original.language = .tr
        original.preferredProviderID = "claude-cli"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SettingsStoreData.self, from: data)

        XCTAssertEqual(decoded.claudeAPIKey, "sk-ant-test")
        XCTAssertEqual(decoded.openaiAPIKey, "sk-test")
        XCTAssertEqual(decoded.language, .tr)
        XCTAssertEqual(decoded.preferredProviderID, "claude-cli")
    }

    /// Critical: settings.json files written by earlier app versions must keep
    /// loading after new fields are added. The tolerant decoder provides
    /// defaults for any missing key.
    func testTolerantDecodeFromLegacyJSON() throws {
        // Mirrors the v1 settings.json shape — no `language` field.
        let legacy = """
        {
          "claudeAPIKey": "legacy",
          "claudeModel": "claude-sonnet-4-5",
          "openaiAPIKey": "",
          "openaiModel": "gpt-4o-mini",
          "ollamaModel": "llama3.2",
          "preferredProviderID": "claude-cli",
          "accentColorHex": "#7C3AED"
        }
        """
        let data = legacy.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SettingsStoreData.self, from: data)
        XCTAssertEqual(decoded.claudeAPIKey, "legacy")
        XCTAssertEqual(decoded.language, .auto,
                       "Missing `language` should default to .auto")
    }

    func testTolerantDecodeFromEmptyObject() throws {
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SettingsStoreData.self, from: data)
        XCTAssertEqual(decoded.claudeAPIKey, "")
        XCTAssertEqual(decoded.claudeModel, "claude-sonnet-4-5")
        XCTAssertEqual(decoded.language, .auto)
    }

    func testSettingsStorePersistsToFile() {
        let store = SettingsStore()
        store.data.claudeAPIKey = "persisted-key"
        store.data.language = .tr

        let url = Persistence.supportDir.appendingPathComponent("settings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let reloaded = SettingsStore()
        XCTAssertEqual(reloaded.data.claudeAPIKey, "persisted-key")
        XCTAssertEqual(reloaded.data.language, .tr)
    }
}
