import XCTest
@testable import NeuraBar

/// The data-location surface is the entry point for "put my stuff in
/// iCloud" — these tests lock the behaviour contract: resolver falls back
/// safely when a target isn't available, migration copies JSON plus the
/// notes-images subtree, and the bootstrap file decides where everything
/// loads from on launch.
final class DataLocationTests: NBTestCase {

    // MARK: - Resolver defaults

    func testResolverFallsBackToApplicationSupportForUnavailableModes() {
        // On CI / dev box without iCloud Drive the resolver must never
        // hand back nil — it falls back to Application Support so the app
        // remains usable.
        var cfg = DataLocationConfig()
        cfg.mode = .iCloudDrive
        let url = DataLocationResolver.resolve(cfg)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testCustomModeWithoutPathFallsBackToApplicationSupport() {
        var cfg = DataLocationConfig()
        cfg.mode = .custom
        cfg.customPath = ""
        let url = DataLocationResolver.resolve(cfg)
        XCTAssertEqual(url.path, DataLocationResolver.applicationSupportURL.path)
    }

    func testCustomModeWithValidPathAppendsNeuraBarSubfolder() {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-data-loc-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        var cfg = DataLocationConfig()
        cfg.mode = .custom
        cfg.customPath = tempBase.path
        let url = DataLocationResolver.resolve(cfg)
        XCTAssertTrue(url.path.hasSuffix("/NeuraBar"))
        XCTAssertTrue(url.path.hasPrefix(tempBase.path))
    }

    // MARK: - Availability

    func testApplicationSupportIsAlwaysAvailable() {
        XCTAssertTrue(DataLocationResolver.isAvailable(.applicationSupport))
    }

    func testCustomRequiresAnExistingDirectory() {
        XCTAssertFalse(DataLocationResolver.isAvailable(.custom, customPath: ""))
        XCTAssertFalse(DataLocationResolver.isAvailable(.custom, customPath: "/tmp/does-not-exist-\(UUID())"))
        XCTAssertTrue(DataLocationResolver.isAvailable(.custom, customPath: "/tmp"))
        // A file (not a directory) should fail the check.
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("nb-not-dir-\(UUID())")
        try? Data([0]).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        XCTAssertFalse(DataLocationResolver.isAvailable(.custom, customPath: f.path))
    }

    // MARK: - Migration

    func testMigrateCopiesJSONFiles() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-src-\(UUID())", isDirectory: true)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-dst-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        try #"{"a":1}"#.write(to: source.appendingPathComponent("a.json"),
                              atomically: true, encoding: .utf8)
        try #"{"b":2}"#.write(to: source.appendingPathComponent("b.json"),
                              atomically: true, encoding: .utf8)

        let copied = try DataLocationResolver.migrate(from: source, to: dest)
        XCTAssertEqual(copied, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("b.json").path))
    }

    func testMigrateSkipsBootstrapFile() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-src-\(UUID())", isDirectory: true)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-dst-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        try "{}".write(to: source.appendingPathComponent("location.json"),
                       atomically: true, encoding: .utf8)
        try #"{"x":1}"#.write(to: source.appendingPathComponent("todos.json"),
                              atomically: true, encoding: .utf8)

        _ = try DataLocationResolver.migrate(from: source, to: dest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("location.json").path),
                       "Bootstrap pointer must not follow the migration — it lives in App Support forever")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("todos.json").path))
    }

    func testMigrateIsIdempotent() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-src-\(UUID())", isDirectory: true)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-dst-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        try "{}".write(to: source.appendingPathComponent("todos.json"),
                       atomically: true, encoding: .utf8)
        let first = try DataLocationResolver.migrate(from: source, to: dest)
        let second = try DataLocationResolver.migrate(from: source, to: dest)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1, "Re-migrating is safe — destination just gets the same file again")
    }

    // MARK: - Tolerant decode for DataLocationConfig

    func testDecodeEmptyConfig() throws {
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DataLocationConfig.self, from: data)
        XCTAssertEqual(decoded.mode, .applicationSupport)
        XCTAssertEqual(decoded.customPath, "")
    }

    // MARK: - Bootstrap round-trip

    func testBootstrapSaveLoadRoundTrip() {
        // NBTestCase redirects Persistence.supportDir to a temp dir. We
        // leverage that here by writing through Persistence.saveDataLocation
        // and reading back.
        var cfg = DataLocationConfig()
        cfg.mode = .iCloudDrive
        Persistence.saveDataLocation(cfg)
        let loaded = Persistence.loadDataLocation()
        XCTAssertEqual(loaded.mode, .iCloudDrive)
    }

    // MARK: - Label metadata

    func testEveryModeHasLabelKeyAndIcon() {
        let l = Localization()
        l.apply(override: .en)
        for mode in DataLocation.allCases {
            XCTAssertFalse(mode.icon.isEmpty, "\(mode) missing icon")
            let label = l.t(mode.labelKey)
            XCTAssertNotEqual(label, mode.labelKey.rawValue,
                              "\(mode) label falls through to raw key")
        }
    }
}
