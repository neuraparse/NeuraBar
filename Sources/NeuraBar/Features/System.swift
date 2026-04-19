import SwiftUI
import Darwin
import IOKit.ps

final class SystemMonitor: ObservableObject {
    @Published var cpu: Double = 0
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var diskFreeGB: Double = 0
    @Published var diskTotalGB: Double = 0
    @Published var batteryLevel: Int = -1
    @Published var batteryCharging: Bool = false

    private var timer: Timer?
    private var prevCPU: host_cpu_load_info = host_cpu_load_info()

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

    var body: some View {
        VStack(spacing: 10) {
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
