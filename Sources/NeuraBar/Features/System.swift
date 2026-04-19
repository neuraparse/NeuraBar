import SwiftUI
import Darwin
import IOKit.ps

// MARK: - Alert config

enum AlertLevel: String, Codable { case ok, warning, critical }

struct SystemAlertConfig: Codable, Equatable {
    var cpuWarn: Double = 75
    var cpuCrit: Double = 90
    var memWarn: Double = 80   // percent
    var memCrit: Double = 92
    var diskFreeWarn: Double = 15   // percent free
    var diskFreeCrit: Double = 5
    var batteryWarn: Int = 25
    var batteryCrit: Int = 10

    var enableCPU: Bool = true
    var enableMemory: Bool = true
    var enableDisk: Bool = true
    var enableBattery: Bool = true
    var postNotifications: Bool = true

    static let `default` = SystemAlertConfig()

    // Tolerant decode so older configs load cleanly.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cpuWarn = (try? c.decode(Double.self, forKey: .cpuWarn)) ?? 75
        cpuCrit = (try? c.decode(Double.self, forKey: .cpuCrit)) ?? 90
        memWarn = (try? c.decode(Double.self, forKey: .memWarn)) ?? 80
        memCrit = (try? c.decode(Double.self, forKey: .memCrit)) ?? 92
        diskFreeWarn = (try? c.decode(Double.self, forKey: .diskFreeWarn)) ?? 15
        diskFreeCrit = (try? c.decode(Double.self, forKey: .diskFreeCrit)) ?? 5
        batteryWarn = (try? c.decode(Int.self, forKey: .batteryWarn)) ?? 25
        batteryCrit = (try? c.decode(Int.self, forKey: .batteryCrit)) ?? 10
        enableCPU = (try? c.decode(Bool.self, forKey: .enableCPU)) ?? true
        enableMemory = (try? c.decode(Bool.self, forKey: .enableMemory)) ?? true
        enableDisk = (try? c.decode(Bool.self, forKey: .enableDisk)) ?? true
        enableBattery = (try? c.decode(Bool.self, forKey: .enableBattery)) ?? true
        postNotifications = (try? c.decode(Bool.self, forKey: .postNotifications)) ?? true
    }
}

final class SystemMonitor: ObservableObject {
    @Published var cpu: Double = 0
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var diskFreeGB: Double = 0
    @Published var diskTotalGB: Double = 0
    @Published var batteryLevel: Int = -1
    @Published var batteryCharging: Bool = false

    @Published var config: SystemAlertConfig {
        didSet { Persistence.save(config, to: "system_alert_config.json") }
    }
    @Published private(set) var alertLevel: AlertLevel = .ok
    @Published private(set) var alertReasons: [String] = []

    private var timer: Timer?
    private var prevCPU: host_cpu_load_info = host_cpu_load_info()
    private var lastAlertLevel: AlertLevel = .ok

    init() {
        self.config = Persistence.load(SystemAlertConfig.self, from: "system_alert_config.json")
            ?? SystemAlertConfig()
    }

    func start() {
        timer?.invalidate()
        _ = readCPU() // prime
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        cpu = readCPU()
        let mem = readMemory()
        memoryUsedGB = mem.used
        memoryTotalGB = mem.total
        let disk = readDisk()
        diskFreeGB = disk.free
        diskTotalGB = disk.total
        let bat = readBattery()
        batteryLevel = bat.level
        batteryCharging = bat.charging

        evaluateAlert()
    }

    // MARK: - Alert evaluation (pure, testable)

    /// Compute the alert level + reasons for a given metric snapshot + config.
    /// Exposed static so tests can pin deterministic inputs.
    static func evaluate(
        cpu: Double,
        memoryUsedGB: Double,
        memoryTotalGB: Double,
        diskFreeGB: Double,
        diskTotalGB: Double,
        batteryLevel: Int,
        batteryCharging: Bool,
        config: SystemAlertConfig
    ) -> (level: AlertLevel, reasons: [String]) {
        var level: AlertLevel = .ok
        var reasons: [String] = []

        func escalate(_ l: AlertLevel) {
            if l == .critical { level = .critical }
            else if l == .warning && level == .ok { level = .warning }
        }

        if config.enableCPU {
            if cpu >= config.cpuCrit {
                escalate(.critical)
                reasons.append("CPU \(Int(cpu))% ≥ \(Int(config.cpuCrit))%")
            } else if cpu >= config.cpuWarn {
                escalate(.warning)
                reasons.append("CPU \(Int(cpu))%")
            }
        }

        if config.enableMemory, memoryTotalGB > 0 {
            let pct = memoryUsedGB / memoryTotalGB * 100
            if pct >= config.memCrit {
                escalate(.critical)
                reasons.append("RAM \(Int(pct))% ≥ \(Int(config.memCrit))%")
            } else if pct >= config.memWarn {
                escalate(.warning)
                reasons.append("RAM \(Int(pct))%")
            }
        }

        if config.enableDisk, diskTotalGB > 0 {
            let freePct = diskFreeGB / diskTotalGB * 100
            if freePct <= config.diskFreeCrit {
                escalate(.critical)
                reasons.append("Disk free \(Int(freePct))% ≤ \(Int(config.diskFreeCrit))%")
            } else if freePct <= config.diskFreeWarn {
                escalate(.warning)
                reasons.append("Disk free \(Int(freePct))%")
            }
        }

        if config.enableBattery, batteryLevel >= 0, !batteryCharging {
            if batteryLevel <= config.batteryCrit {
                escalate(.critical)
                reasons.append("Battery \(batteryLevel)% ≤ \(config.batteryCrit)%")
            } else if batteryLevel <= config.batteryWarn {
                escalate(.warning)
                reasons.append("Battery \(batteryLevel)%")
            }
        }

        return (level, reasons)
    }

    private func evaluateAlert() {
        let (level, reasons) = Self.evaluate(
            cpu: cpu,
            memoryUsedGB: memoryUsedGB,
            memoryTotalGB: memoryTotalGB,
            diskFreeGB: diskFreeGB,
            diskTotalGB: diskTotalGB,
            batteryLevel: batteryLevel,
            batteryCharging: batteryCharging,
            config: config
        )
        alertLevel = level
        alertReasons = reasons

        // Fire a notification only when we first cross into critical — avoid
        // spamming the user every tick.
        if level == .critical, lastAlertLevel != .critical, config.postNotifications {
            NotificationService.post(
                title: L.t(.sys_alert_title),
                body: reasons.joined(separator: " · ")
            )
        }
        lastAlertLevel = level
    }

    private func readCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = Double(info.cpu_ticks.0 - prevCPU.cpu_ticks.0)
        let sys = Double(info.cpu_ticks.1 - prevCPU.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 - prevCPU.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 - prevCPU.cpu_ticks.3)
        let total = user + sys + idle + nice
        prevCPU = info
        guard total > 0 else { return 0 }
        return (user + sys + nice) / total * 100
    }

    private func readMemory() -> (used: Double, total: Double) {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = (active + wired + compressed) / 1_073_741_824

        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return (used, total)
    }

    private func readDisk() -> (free: Double, total: Double) {
        // statfs is cheaper than URLResourceValues and doesn't trigger cache_delete
        // daemon logging (which spams GetAPFSVolumeRole debug lines).
        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return (0, 0) }
        let blockSize = Double(stats.f_bsize)
        let free = Double(stats.f_bavail) * blockSize / 1_073_741_824
        let total = Double(stats.f_blocks) * blockSize / 1_073_741_824
        return (free, total)
    }

    private func readBattery() -> (level: Int, charging: Bool) {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef],
              let ps = sources.first,
              let info = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any] else {
            return (-1, false)
        }
        let cur = info[kIOPSCurrentCapacityKey as String] as? Int ?? -1
        let max = info[kIOPSMaxCapacityKey as String] as? Int ?? 100
        let charging = (info[kIOPSIsChargingKey as String] as? Bool) ?? false
        let percent = max > 0 ? (cur * 100 / max) : -1
        return (percent, charging)
    }
}

struct SystemView: View {
    @EnvironmentObject var mon: SystemMonitor
    @EnvironmentObject var l10n: Localization
    @State private var showThresholds = false

    var body: some View {
        VStack(spacing: 10) {
            alertHeader
            StatCard(
                icon: "cpu",
                title: l10n.t(.sys_cpu),
                value: String(format: "%.0f%%", mon.cpu),
                progress: mon.cpu / 100,
                gradient: [.orange, .red]
            )
            StatCard(
                icon: "memorychip",
                title: l10n.t(.sys_memory),
                value: String(format: "%.1f / %.0f GB", mon.memoryUsedGB, mon.memoryTotalGB),
                progress: mon.memoryTotalGB > 0 ? mon.memoryUsedGB / mon.memoryTotalGB : 0,
                gradient: [.purple, .blue]
            )
            StatCard(
                icon: "internaldrive",
                title: l10n.t(.sys_disk),
                value: String(format: "%.0f / %.0f GB %@", mon.diskFreeGB, mon.diskTotalGB, l10n.t(.sys_free)),
                progress: mon.diskTotalGB > 0 ? 1 - (mon.diskFreeGB / mon.diskTotalGB) : 0,
                gradient: [.cyan, .teal]
            )
            if showThresholds {
                thresholdsPanel
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
            if mon.batteryLevel >= 0 {
                StatCard(
                    icon: mon.batteryCharging ? "battery.100.bolt" : "battery.75",
                    title: l10n.t(.sys_battery) + (mon.batteryCharging ? " (\(l10n.t(.sys_charging)))" : ""),
                    value: "\(mon.batteryLevel)%",
                    progress: Double(mon.batteryLevel) / 100,
                    gradient: [.green, .mint]
                )
            }
            Spacer()
        }
        .animation(.spring(duration: 0.22, bounce: 0.15), value: showThresholds)
    }

    // MARK: - Status header

    private var alertHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(alertColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(alertColor.opacity(0.4), lineWidth: 5)
                        .scaleEffect(mon.alertLevel == .ok ? 1 : 1.8)
                        .opacity(mon.alertLevel == .ok ? 0 : 0.5)
                        .animation(
                            mon.alertLevel == .ok
                                ? .default
                                : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: mon.alertLevel
                        )
                )
            VStack(alignment: .leading, spacing: 0) {
                Text(alertTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(alertColor)
                if !mon.alertReasons.isEmpty {
                    Text(mon.alertReasons.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                withAnimation { showThresholds.toggle() }
            } label: {
                Image(systemName: showThresholds ? "chevron.up" : "slider.horizontal.3")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PressableStyle())
            .help(l10n.t(.sys_configure))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(alertColor.opacity(mon.alertLevel == .ok ? 0.04 : 0.1))
        )
    }

    private var alertColor: Color {
        switch mon.alertLevel {
        case .ok: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var alertTitle: String {
        switch mon.alertLevel {
        case .ok: return l10n.t(.sys_status_ok)
        case .warning: return l10n.t(.sys_status_warning)
        case .critical: return l10n.t(.sys_status_critical)
        }
    }

    // MARK: - Thresholds panel

    private var thresholdsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t(.sys_thresholds))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            thresholdRow(
                enabled: $mon.config.enableCPU,
                label: l10n.t(.sys_cpu),
                warn: $mon.config.cpuWarn,
                crit: $mon.config.cpuCrit,
                range: 30...99,
                suffix: "%"
            )
            thresholdRow(
                enabled: $mon.config.enableMemory,
                label: l10n.t(.sys_memory),
                warn: $mon.config.memWarn,
                crit: $mon.config.memCrit,
                range: 30...99,
                suffix: "%"
            )
            thresholdRow(
                enabled: $mon.config.enableDisk,
                label: l10n.t(.sys_disk),
                warn: Binding(
                    get: { 100 - mon.config.diskFreeWarn },
                    set: { mon.config.diskFreeWarn = 100 - $0 }
                ),
                crit: Binding(
                    get: { 100 - mon.config.diskFreeCrit },
                    set: { mon.config.diskFreeCrit = 100 - $0 }
                ),
                range: 50...99,
                suffix: "%"
            )
            if mon.batteryLevel >= 0 {
                thresholdRow(
                    enabled: $mon.config.enableBattery,
                    label: l10n.t(.sys_battery),
                    warn: Binding(
                        get: { Double(mon.config.batteryWarn) },
                        set: { mon.config.batteryWarn = Int($0) }
                    ),
                    crit: Binding(
                        get: { Double(mon.config.batteryCrit) },
                        set: { mon.config.batteryCrit = Int($0) }
                    ),
                    range: 5...50,
                    suffix: "%",
                    reversed: true
                )
            }

            Toggle(isOn: $mon.config.postNotifications) {
                Text(l10n.t(.sys_notify))
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.top, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }

    /// reversed = true when the metric fires when it falls BELOW the threshold
    /// (battery), so the slider semantics match the alert.
    private func thresholdRow(
        enabled: Binding<Bool>,
        label: String,
        warn: Binding<Double>,
        crit: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String,
        reversed: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Toggle("", isOn: enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                Text(label).font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(warn.wrappedValue))\(suffix) · \(Int(crit.wrappedValue))\(suffix)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if enabled.wrappedValue {
                HStack(spacing: 4) {
                    Slider(value: warn, in: range)
                        .tint(.orange)
                    Slider(value: crit, in: range)
                        .tint(.red)
                }
                .controlSize(.mini)
            }
        }
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let progress: Double
    let gradient: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * CGFloat(min(max(progress, 0), 1))), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
