import Foundation
import SwiftUI

/// Where NeuraBar keeps its JSON stores + note images on disk.
///
/// macOS's proper iCloud story (ubiquity containers via CloudKit) is
/// restricted to apps signed with a paid Apple Developer ID and distributed
/// through the App Store. NeuraBar ships ad-hoc signed, so we use a
/// pragmatic alternative: point our data directory at any folder —
/// including the iCloud Drive desktop sync folder or Google Drive's
/// desktop client folder. The third-party sync daemons then pick up file
/// changes and sync them for us.
enum DataLocation: String, Codable, CaseIterable, Identifiable, Equatable {
    case applicationSupport
    case iCloudDrive
    case googleDrive
    case custom

    var id: String { rawValue }

    var labelKey: Loc {
        switch self {
        case .applicationSupport: return .data_loc_local
        case .iCloudDrive:        return .data_loc_icloud
        case .googleDrive:        return .data_loc_gdrive
        case .custom:             return .data_loc_custom
        }
    }

    var icon: String {
        switch self {
        case .applicationSupport: return "internaldrive"
        case .iCloudDrive:        return "icloud.fill"
        case .googleDrive:        return "folder.fill.badge.person.crop"
        case .custom:             return "folder.fill"
        }
    }
}

struct DataLocationConfig: Codable, Equatable {
    var mode: DataLocation = .applicationSupport
    var customPath: String = ""

    static let `default` = DataLocationConfig()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decode(DataLocation.self, forKey: .mode)) ?? .applicationSupport
        customPath = (try? c.decode(String.self, forKey: .customPath)) ?? ""
    }
}

/// Resolves DataLocation to a concrete URL and handles probing / migrating.
enum DataLocationResolver {

    /// Default: ~/Library/Application Support/NeuraBar/
    static var applicationSupportURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return base.appendingPathComponent("NeuraBar", isDirectory: true)
    }

    /// iCloud Drive desktop sync folder that the iCloud Drive client creates
    /// at `~/Library/Mobile Documents/com~apple~CloudDocs/`. Returning nil
    /// means the user doesn't have iCloud Drive desktop sync enabled.
    static var iCloudDriveURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudDocs = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: cloudDocs.path) else { return nil }
        return cloudDocs.appendingPathComponent("NeuraBar", isDirectory: true)
    }

    /// Google Drive desktop clients mount either under
    /// `~/Library/CloudStorage/GoogleDrive-<email>/My Drive/` (newer client)
    /// or a legacy `~/Google Drive/` symlink. Returns the first match.
    static var googleDriveURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let legacy = home.appendingPathComponent("Google Drive", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacy.path) {
            return legacy.appendingPathComponent("NeuraBar", isDirectory: true)
        }
        let cloudStorage = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: cloudStorage, includingPropertiesForKeys: nil
        ) {
            for url in entries where url.lastPathComponent.hasPrefix("GoogleDrive-") {
                let myDrive = url.appendingPathComponent("My Drive", isDirectory: true)
                if FileManager.default.fileExists(atPath: myDrive.path) {
                    return myDrive.appendingPathComponent("NeuraBar", isDirectory: true)
                }
            }
        }
        return nil
    }

    /// Availability check for the UI — are we actually able to resolve this
    /// mode to a real directory?
    static func isAvailable(_ mode: DataLocation, customPath: String = "") -> Bool {
        switch mode {
        case .applicationSupport: return true
        case .iCloudDrive:        return iCloudDriveURL != nil
        case .googleDrive:        return googleDriveURL != nil
        case .custom:
            guard !customPath.isEmpty else { return false }
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: customPath, isDirectory: &isDir)
            return exists && isDir.boolValue
        }
    }

    /// Resolve to a URL, creating the directory if needed. Returns the
    /// Application Support fallback when the requested mode isn't available.
    @discardableResult
    static func resolve(_ config: DataLocationConfig) -> URL {
        let url: URL
        switch config.mode {
        case .applicationSupport:
            url = applicationSupportURL
        case .iCloudDrive:
            url = iCloudDriveURL ?? applicationSupportURL
        case .googleDrive:
            url = googleDriveURL ?? applicationSupportURL
        case .custom:
            if !config.customPath.isEmpty {
                let candidate = URL(fileURLWithPath: config.customPath, isDirectory: true)
                url = candidate.appendingPathComponent("NeuraBar", isDirectory: true)
            } else {
                url = applicationSupportURL
            }
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true
            )
        }
        return url
    }

    /// Copy every JSON file + the `notes-images/` subtree from `source` to
    /// `destination`. Non-destructive — existing files in destination with
    /// the same name are overwritten, but nothing is removed from source
    /// (users can reclaim the old folder themselves).
    @discardableResult
    static func migrate(from source: URL, to destination: URL) throws -> Int {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        guard fm.fileExists(atPath: source.path) else { return 0 }
        guard source.path != destination.path else { return 0 }

        var copied = 0
        let contents = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for item in contents {
            // Skip the bootstrap file — it must stay in Application Support
            // or we'd lose the pointer to wherever the user moved things.
            if item.lastPathComponent == "location.json" { continue }
            let dest = destination.appendingPathComponent(item.lastPathComponent)
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: item, to: dest)
            copied += 1
        }
        return copied
    }
}

// MARK: - Settings card

struct DataLocationCard: View {
    @EnvironmentObject var l10n: Localization
    @State private var config: DataLocationConfig = Persistence.loadDataLocation()
    @State private var currentPath: String = Persistence.supportDir.path
    @State private var migrating = false
    @State private var lastResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NB.sp3) {
            HStack(spacing: 6) {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.blue)
                Text(l10n.t(.data_loc_title))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            Text(l10n.t(.data_loc_explanation))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(DataLocation.allCases) { loc in
                    row(for: loc)
                }
            }

            if config.mode == .custom {
                HStack {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(config.customPath.isEmpty ? l10n.t(.data_loc_pickFolder) : config.customPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(l10n.t(.shortcut_pick)) {
                        pickCustomFolder()
                    }
                    .controlSize(.small)
                }
            }

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t(.data_loc_current))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(currentPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: currentPath))
                } label: {
                    Label(l10n.t(.set_revealFolder), systemImage: "folder")
                        .font(.caption)
                }
                Spacer()
                if migrating {
                    ProgressView().controlSize(.small)
                }
                if let result = lastResult {
                    Text(result)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(NB.sp4)
        .nbCard()
    }

    @ViewBuilder
    private func row(for loc: DataLocation) -> some View {
        let available = DataLocationResolver.isAvailable(loc, customPath: config.customPath)
        let selected = config.mode == loc
        Button {
            if available || loc == .custom {
                select(loc)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Image(systemName: loc.icon)
                    .foregroundStyle(available ? .primary : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(l10n.t(loc.labelKey))
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(available ? .primary : .secondary)
                    if !available && loc != .custom {
                        Text(l10n.t(.data_loc_notAvailable))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!available && loc != .custom)
    }

    private func select(_ loc: DataLocation) {
        guard config.mode != loc else { return }
        var newConfig = config
        newConfig.mode = loc
        applyChange(newConfig)
    }

    private func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            var newConfig = config
            newConfig.mode = .custom
            newConfig.customPath = url.path
            applyChange(newConfig)
        }
    }

    private func applyChange(_ newConfig: DataLocationConfig) {
        migrating = true
        lastResult = nil
        let oldURL = Persistence.supportDir
        let newURL = DataLocationResolver.resolve(newConfig)

        DispatchQueue.global(qos: .userInitiated).async {
            var copied = 0
            if oldURL.path != newURL.path {
                copied = (try? DataLocationResolver.migrate(from: oldURL, to: newURL)) ?? 0
            }
            DispatchQueue.main.async {
                Persistence.saveDataLocation(newConfig)
                Persistence.applyDataLocation(newConfig)
                self.config = newConfig
                self.currentPath = Persistence.supportDir.path
                self.migrating = false
                self.lastResult = copied > 0
                    ? L.t(.data_loc_migrated, copied)
                    : L.t(.data_loc_switched)
            }
        }
    }
}
