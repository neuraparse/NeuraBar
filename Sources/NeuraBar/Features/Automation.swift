import SwiftUI
import AppKit

// MARK: - Model

enum AutomationCategory: String, Codable {
    case files, cleanup, system
}

enum AutomationStatus: String, Codable {
    case succeeded, failed
}

struct AutomationStat: Codable, Hashable {
    let label: String   // already localized at time of run
    let value: String
}

struct AutomationRun: Identifiable, Codable {
    let id: UUID
    let taskID: String
    let taskTitle: String
    let status: AutomationStatus
    let summary: String
    let stats: [AutomationStat]
    let details: String
    let startedAt: Date
    let finishedAt: Date

    var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
}

struct AutomationDef: Identifiable {
    let id: String
    let category: AutomationCategory
    let titleKey: Loc
    let subtitleKey: Loc
    let icon: String
    let color: Color
    let action: () async -> (summary: String, stats: [AutomationStat], details: String, failed: Bool)
}

// MARK: - Store (tracks history)

final class AutomationStore: ObservableObject {
    @Published var history: [AutomationRun] = [] {
        didSet { Persistence.save(history, to: "automation_history.json") }
    }
    @Published var runningTaskID: String?

    init() {
        if let saved = Persistence.load([AutomationRun].self, from: "automation_history.json") {
            self.history = saved
        }
    }

    func clearHistory() { history.removeAll() }

    @MainActor
    func run(_ def: AutomationDef, l10n: Localization) async {
        runningTaskID = def.id
        let started = Date()
        let result = await def.action()
        let finished = Date()
        let run = AutomationRun(
            id: UUID(),
            taskID: def.id,
            taskTitle: l10n.t(def.titleKey),
            status: result.failed ? .failed : .succeeded,
            summary: result.summary,
            stats: result.stats,
            details: result.details,
            startedAt: started,
            finishedAt: finished
        )
        history.insert(run, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        runningTaskID = nil
    }
}

// MARK: - View

struct AutomationView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var l10n: Localization
    @State private var expandedRunID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    historyBlock
                    categoryBlock(.files)
                    categoryBlock(.cleanup)
                    categoryBlock(.system)
                }
            }
        }
    }

    // MARK: History

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l10n.t(.auto_history))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                if !store.automation.history.isEmpty {
                    Button {
                        store.automation.clearHistory()
                    } label: {
                        Text(l10n.t(.auto_clearHistory))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if store.automation.history.isEmpty {
                Text(l10n.t(.auto_noRuns))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(store.automation.history.prefix(3)) { run in
                        RunCard(run: run, expanded: expandedRunID == run.id) {
                            withAnimation(.spring(duration: 0.22, bounce: 0.15)) {
                                expandedRunID = expandedRunID == run.id ? nil : run.id
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Category

    @ViewBuilder
    private func categoryBlock(_ cat: AutomationCategory) -> some View {
        let defs = AutomationCatalog.all.filter { $0.category == cat }
        if !defs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(categoryTitle(cat))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .padding(.top, 4)
                VStack(spacing: 5) {
                    ForEach(defs) { def in
                        AutomationRow(def: def, isRunning: store.automation.runningTaskID == def.id)
                            .environmentObject(l10n)
                            .environmentObject(store)
                    }
                }
            }
        }
    }

    private func categoryTitle(_ cat: AutomationCategory) -> String {
        switch cat {
        case .files: return l10n.t(.auto_category_files)
        case .cleanup: return l10n.t(.auto_category_cleanup)
        case .system: return l10n.t(.auto_category_system)
        }
    }
}

// MARK: - Row

struct AutomationRow: View {
    let def: AutomationDef
    let isRunning: Bool
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var l10n: Localization
    @State private var hover = false

    var body: some View {
        Button {
            Task { await store.automation.run(def, l10n: l10n) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(def.color.opacity(0.18)).frame(width: 28, height: 28)
                    Image(systemName: def.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(def.color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.t(def.titleKey))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(l10n.t(def.subtitleKey))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if isRunning {
                    ProgressView().scaleEffect(0.5)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                    .fill(Color.primary.opacity(hover ? 0.08 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .disabled(isRunning)
    }
}

// MARK: - Run card (expandable)

struct RunCard: View {
    let run: AutomationRun
    let expanded: Bool
    let toggle: () -> Void

    @EnvironmentObject var l10n: Localization

    var statusColor: Color {
        run.status == .succeeded ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(run.taskTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(run.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(expanded ? nil : 1)
                    }
                    Spacer()
                    Text(run.startedAt, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            if expanded {
                if !run.stats.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(run.stats, id: \.self) { stat in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stat.value)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text(stat.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(l10n.t(.auto_stat_duration))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(formatDuration(run.duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if !run.details.isEmpty {
                        ScrollView {
                            Text(run.details)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 140)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25))
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NB.rMd, style: .continuous)
                .strokeBorder(statusColor.opacity(0.25), lineWidth: 0.7)
        )
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        if d < 1 { return String(format: "%.0f ms", d * 1000) }
        if d < 60 { return String(format: "%.1f s", d) }
        return String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}

// MARK: - Shell runner

private func runSh(_ cmd: String) -> (stdout: String, code: Int32) {
    let task = Process()
    task.launchPath = "/bin/zsh"
    task.arguments = ["-c", cmd]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", task.terminationStatus)
    } catch {
        return ("Error: \(error.localizedDescription)", -1)
    }
}

private func humanBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useAll]
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}

private func dirSize(_ path: String) -> Int64 {
    let (out, _) = runSh("du -sk \(escape(path)) 2>/dev/null | cut -f1")
    let kb = Int64(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    return kb * 1024
}

private func escape(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func stat(_ key: Loc, _ value: String) -> AutomationStat {
    AutomationStat(label: L.t(key), value: value)
}

// MARK: - Catalog

enum AutomationCatalog {
    static let all: [AutomationDef] = [
        // FILES
        .init(id: "screenshots", category: .files, titleKey: .auto_screenshots_title, subtitleKey: .auto_screenshots_sub,
              icon: "photo.stack", color: .blue, action: organizeScreenshots),
        .init(id: "sortDL", category: .files, titleKey: .auto_sortDL_title, subtitleKey: .auto_sortDL_sub,
              icon: "folder.badge.gearshape", color: .blue, action: sortDownloads),
        .init(id: "heic", category: .files, titleKey: .auto_heic_title, subtitleKey: .auto_heic_sub,
              icon: "arrow.triangle.2.circlepath", color: .blue, action: convertHEICToJPG),
        .init(id: "bigFiles", category: .files, titleKey: .auto_bigFiles_title, subtitleKey: .auto_bigFiles_sub,
              icon: "chart.bar.doc.horizontal", color: .blue, action: largeFileReport),
        .init(id: "oldDL", category: .files, titleKey: .auto_oldDownloads_title, subtitleKey: .auto_oldDownloads_sub,
              icon: "archivebox", color: .blue, action: archiveOldDownloads),
        // CLEANUP
        .init(id: "dmg", category: .cleanup, titleKey: .auto_dmg_title, subtitleKey: .auto_dmg_sub,
              icon: "arrow.down.doc", color: .pink, action: cleanInstallers),
        .init(id: "dsstore", category: .cleanup, titleKey: .auto_dsstore_title, subtitleKey: .auto_dsstore_sub,
              icon: "trash.slash", color: .pink, action: cleanDSStore),
        .init(id: "trash", category: .cleanup, titleKey: .auto_trash_title, subtitleKey: .auto_trash_sub,
              icon: "trash", color: .pink, action: emptyTrash),
        .init(id: "derived", category: .cleanup, titleKey: .auto_derived_title, subtitleKey: .auto_derived_sub,
              icon: "hammer", color: .pink, action: cleanDerivedData),
        // SYSTEM
        .init(id: "hidden", category: .system, titleKey: .auto_hiddenFiles_title, subtitleKey: .auto_hiddenFiles_sub,
              icon: "eye", color: .teal, action: toggleHiddenFiles),
        .init(id: "lock", category: .system, titleKey: .auto_lockScreen_title, subtitleKey: .auto_lockScreen_sub,
              icon: "lock.fill", color: .teal, action: lockScreen),
        .init(id: "sleep", category: .system, titleKey: .auto_sleep_title, subtitleKey: .auto_sleep_sub,
              icon: "moon.fill", color: .teal, action: sleepDisplay)
    ]
}

// MARK: - Actions

typealias ActionResult = (summary: String, stats: [AutomationStat], details: String, failed: Bool)

func organizeScreenshots() async -> ActionResult {
    let cmd = """
    setopt NULL_GLOB
    cd ~/Desktop || exit 1
    mkdir -p Screenshots
    moved=0
    for f in Screenshot*.{png,jpg,heic,HEIC}; do
      [ -e "$f" ] || continue
      attr=$(stat -f "%Sm" -t "%Y-%m" "$f")
      mkdir -p "Screenshots/$attr"
      mv "$f" "Screenshots/$attr/"
      moved=$((moved+1))
      echo "→ Screenshots/$attr/$f"
    done
    echo "__MOVED:$moved"
    """
    let (out, code) = runSh(cmd)
    let moved = parseCounter(out, key: "__MOVED")
    let details = out.replacingOccurrences(of: "__MOVED:\(moved)", with: "")
    let summary = L.t(.auto_stat_moved) + ": \(moved)"
    return (summary, [stat(.auto_stat_moved, "\(moved)")], details.trimmingCharacters(in: .whitespacesAndNewlines), code != 0)
}

func cleanInstallers() async -> ActionResult {
    let cmd = """
    setopt NULL_GLOB
    cd ~/Downloads || exit 1
    mkdir -p _silinecek
    moved=0
    size=0
    for f in *.{dmg,pkg,msi,exe}; do
      [ -e "$f" ] || continue
      sz=$(stat -f "%z" "$f" 2>/dev/null || echo 0)
      size=$((size+sz))
      mv "$f" _silinecek/
      moved=$((moved+1))
      echo "→ _silinecek/$f ($sz bytes)"
    done
    echo "__MOVED:$moved"
    echo "__SIZE:$size"
    """
    let (out, code) = runSh(cmd)
    let moved = parseCounter(out, key: "__MOVED")
    let size = parseCounter(out, key: "__SIZE")
    let details = stripCounters(out, keys: ["__MOVED", "__SIZE"])
    return (L.t(.auto_stat_moved) + ": \(moved)",
            [stat(.auto_stat_moved, "\(moved)"),
             stat(.auto_stat_size, humanBytes(Int64(size)))],
            details, code != 0)
}

func sortDownloads() async -> ActionResult {
    let cmd = """
    setopt NULL_GLOB
    cd ~/Downloads || exit 1
    mkdir -p PDFs Images Videos Documents Archives Audio
    moved=0
    for f in *.*; do
      [ -e "$f" ] || continue
      [ -d "$f" ] && continue
      ext="${f##*.}"
      ext="${ext:l}"
      case "$ext" in
        pdf)                                  dest="PDFs" ;;
        png|jpg|jpeg|heic|gif|webp|bmp|svg)   dest="Images" ;;
        mp4|mov|mkv|avi|webm|m4v)             dest="Videos" ;;
        doc|docx|txt|md|rtf|pages|odt|xlsx|csv) dest="Documents" ;;
        zip|tar|gz|rar|7z|bz2|xz)             dest="Archives" ;;
        mp3|m4a|wav|flac|aac|ogg)             dest="Audio" ;;
        *) continue ;;
      esac
      mv "$f" "$dest/"
      moved=$((moved+1))
      echo "→ $dest/$f"
    done
    echo "__MOVED:$moved"
    """
    let (out, code) = runSh(cmd)
    let moved = parseCounter(out, key: "__MOVED")
    return (L.t(.auto_stat_moved) + ": \(moved)",
            [stat(.auto_stat_moved, "\(moved)")],
            stripCounters(out, keys: ["__MOVED"]), code != 0)
}

func cleanDSStore() async -> ActionResult {
    let (out, code) = runSh("find ~ -name .DS_Store -type f -print -delete 2>/dev/null | wc -l")
    let n = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    return (L.t(.auto_stat_deleted) + ": \(n)",
            [stat(.auto_stat_deleted, "\(n)")],
            "",
            code != 0)
}

func convertHEICToJPG() async -> ActionResult {
    let cmd = """
    setopt NULL_GLOB
    cd ~/Desktop || exit 1
    converted=0
    skipped=0
    for f in *.{heic,HEIC}; do
      [ -e "$f" ] || continue
      base="${f%.*}"
      if [ -e "$base.jpg" ]; then
        echo "skipped (exists): $base.jpg"
        skipped=$((skipped+1))
        continue
      fi
      if sips -s format jpeg "$f" --out "$base.jpg" >/dev/null 2>&1; then
        converted=$((converted+1))
        echo "→ $base.jpg"
      fi
    done
    echo "__CONV:$converted"
    echo "__SKIP:$skipped"
    """
    let (out, code) = runSh(cmd)
    let c = parseCounter(out, key: "__CONV")
    let s = parseCounter(out, key: "__SKIP")
    return (L.t(.auto_stat_converted) + ": \(c)",
            [stat(.auto_stat_converted, "\(c)"),
             stat(.auto_stat_skipped, "\(s)")],
            stripCounters(out, keys: ["__CONV", "__SKIP"]), code != 0)
}

func largeFileReport() async -> ActionResult {
    let cmd = """
    {
      find ~/Downloads ~/Desktop -type f -not -path '*/.*' -print0 2>/dev/null \
        | xargs -0 du -h 2>/dev/null
    } | sort -rh | head -20
    """
    let (out, code) = runSh(cmd)
    let lines = out.split(separator: "\n")
    return (L.t(.auto_stat_total) + ": \(lines.count)",
            [stat(.auto_stat_total, "\(lines.count)")],
            out, code != 0)
}

func archiveOldDownloads() async -> ActionResult {
    let cmd = """
    setopt NULL_GLOB
    cd ~/Downloads || exit 1
    mkdir -p _arsiv
    moved=0
    size=0
    while IFS= read -r f; do
      [ -e "$f" ] || continue
      [ "$f" = "_arsiv" ] && continue
      sz=$(stat -f "%z" "$f" 2>/dev/null || echo 0)
      size=$((size+sz))
      mv "$f" _arsiv/
      moved=$((moved+1))
      echo "→ _arsiv/$(basename "$f")"
    done < <(find . -maxdepth 1 -mindepth 1 -mtime +30 -not -name "_*" -not -name ".*")
    echo "__MOVED:$moved"
    echo "__SIZE:$size"
    """
    let (out, code) = runSh(cmd)
    let moved = parseCounter(out, key: "__MOVED")
    let size = parseCounter(out, key: "__SIZE")
    return (L.t(.auto_stat_moved) + ": \(moved)",
            [stat(.auto_stat_moved, "\(moved)"),
             stat(.auto_stat_size, humanBytes(Int64(size)))],
            stripCounters(out, keys: ["__MOVED", "__SIZE"]), code != 0)
}

func emptyTrash() async -> ActionResult {
    let trashes = ["~/.Trash"]
    var totalBytes: Int64 = 0
    var details = ""
    for t in trashes {
        let path = NSString(string: t).expandingTildeInPath
        let sz = dirSize(path)
        totalBytes += sz
        details += "\(path): \(humanBytes(sz))\n"
    }
    let script = "osascript -e 'tell application \"Finder\" to empty trash' 2>&1"
    let (out, code) = runSh(script)
    details += out
    return ("Freed \(humanBytes(totalBytes))",
            [stat(.auto_stat_size, humanBytes(totalBytes))],
            details.trimmingCharacters(in: .whitespacesAndNewlines), code != 0)
}

func cleanDerivedData() async -> ActionResult {
    let base = NSString(string: "~/Library/Developer/Xcode/DerivedData").expandingTildeInPath
    let size = dirSize(base)
    if !FileManager.default.fileExists(atPath: base) {
        return ("DerivedData not found", [], "\(base) does not exist.", false)
    }
    let (out, code) = runSh("rm -rf \(escape(base))/* 2>&1 && echo done")
    return ("Freed \(humanBytes(size))",
            [stat(.auto_stat_size, humanBytes(size))],
            out.trimmingCharacters(in: .whitespacesAndNewlines), code != 0)
}

func toggleHiddenFiles() async -> ActionResult {
    let (curOut, _) = runSh("defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo 0")
    let cur = curOut.trimmingCharacters(in: .whitespacesAndNewlines)
    let wasShown = (cur == "1" || cur.uppercased() == "TRUE")
    let newValue = wasShown ? "FALSE" : "TRUE"
    let (out, code) = runSh("defaults write com.apple.finder AppleShowAllFiles \(newValue) && killall Finder")
    return (wasShown ? "Hidden files: OFF" : "Hidden files: ON",
            [stat(.auto_stat_total, wasShown ? "OFF" : "ON")],
            out, code != 0)
}

func lockScreen() async -> ActionResult {
    let (out, code) = runSh("pmset displaysleepnow")
    return ("Locked", [], out, code != 0)
}

func sleepDisplay() async -> ActionResult {
    let (out, code) = runSh("pmset displaysleepnow")
    return ("Display slept", [], out, code != 0)
}

// MARK: - Counter parsing (internal — exercised by tests)

func parseCounter(_ text: String, key: String) -> Int {
    for line in text.split(separator: "\n") {
        if line.hasPrefix("\(key):") {
            return Int(line.dropFirst(key.count + 1)) ?? 0
        }
    }
    return 0
}

func stripCounters(_ text: String, keys: [String]) -> String {
    text.split(separator: "\n")
        .filter { line in !keys.contains(where: { line.hasPrefix("\($0):") }) }
        .joined(separator: "\n")
}
