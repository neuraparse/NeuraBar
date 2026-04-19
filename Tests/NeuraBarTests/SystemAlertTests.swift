import XCTest
@testable import NeuraBar

/// Exercises the pure threshold logic. Live metric reads are OS-dependent so
/// we test via `SystemMonitor.evaluate(...)` with deterministic inputs.
final class SystemAlertTests: XCTestCase {

    private let defaults = SystemAlertConfig()

    // MARK: - Baseline

    func testHealthyStateReturnsOK() {
        let (level, reasons) = SystemMonitor.evaluate(
            cpu: 15,
            memoryUsedGB: 4, memoryTotalGB: 32,
            diskFreeGB: 200, diskTotalGB: 500,
            batteryLevel: 80, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .ok)
        XCTAssertTrue(reasons.isEmpty)
    }

    // MARK: - CPU

    func testCPUAtWarningThresholdFires() {
        let (level, reasons) = SystemMonitor.evaluate(
            cpu: 76, // just above 75
            memoryUsedGB: 4, memoryTotalGB: 32,
            diskFreeGB: 200, diskTotalGB: 500,
            batteryLevel: 80, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .warning)
        XCTAssertTrue(reasons.contains(where: { $0.contains("CPU") }))
    }

    func testCPUAtCriticalThresholdFires() {
        let (level, _) = SystemMonitor.evaluate(
            cpu: 95,
            memoryUsedGB: 4, memoryTotalGB: 32,
            diskFreeGB: 200, diskTotalGB: 500,
            batteryLevel: 80, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .critical)
    }

    func testDisabledMetricDoesntTrigger() {
        var config = defaults
        config.enableCPU = false
        let (level, _) = SystemMonitor.evaluate(
            cpu: 99,
            memoryUsedGB: 4, memoryTotalGB: 32,
            diskFreeGB: 200, diskTotalGB: 500,
            batteryLevel: 80, batteryCharging: false,
            config: config
        )
        XCTAssertEqual(level, .ok)
    }

    // MARK: - Memory

    func testMemoryPercentAboveCrit() {
        // 30 of 32 = ~93% which is above 92
        let (level, reasons) = SystemMonitor.evaluate(
            cpu: 15,
            memoryUsedGB: 30, memoryTotalGB: 32,
            diskFreeGB: 200, diskTotalGB: 500,
            batteryLevel: 80, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .critical)
        XCTAssertTrue(reasons.contains(where: { $0.contains("RAM") }))
    }

    func testMemoryZeroTotalIsSkipped() {
        // Defensive: if readMemory returned 0s we must not divide by zero.
        let (level, _) = SystemMonitor.evaluate(
            cpu: 0,
            memoryUsedGB: 0, memoryTotalGB: 0,
            diskFreeGB: 100, diskTotalGB: 100,
            batteryLevel: 50, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .ok)
    }

    // MARK: - Disk

    func testDiskFreePercentBelowWarn() {
        // 10 GB free of 100 = 10% free, defaults warn at 15% free
        let (level, reasons) = SystemMonitor.evaluate(
            cpu: 10,
            memoryUsedGB: 1, memoryTotalGB: 32,
            diskFreeGB: 10, diskTotalGB: 100,
            batteryLevel: 80, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .warning)
        XCTAssertTrue(reasons.contains(where: { $0.lowercased().contains("disk") }))
    }

    func testDiskFreePercentBelowCrit() {
        // 3% free, defaults crit at 5%
        let (level, _) = SystemMonitor.evaluate(
            cpu: 10,
            memoryUsedGB: 1, memoryTotalGB: 32,
            diskFreeGB: 3, diskTotalGB: 100,
            batteryLevel: 80, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .critical)
    }

    // MARK: - Battery

    func testBatteryLowWhileDischargingFires() {
        let (level, reasons) = SystemMonitor.evaluate(
            cpu: 10, memoryUsedGB: 1, memoryTotalGB: 32,
            diskFreeGB: 200, diskTotalGB: 500,
            batteryLevel: 18, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .warning)
        XCTAssertTrue(reasons.contains(where: { $0.contains("Battery") }))
    }

    func testBatteryLowWhileChargingDoesNotFire() {
        // Plugging in should silence the battery alert even at 5%.
        let (level, _) = SystemMonitor.evaluate(
            cpu: 10, memoryUsedGB: 1, memoryTotalGB: 32,
            diskFreeGB: 200, diskTotalGB: 500,
            batteryLevel: 5, batteryCharging: true,
            config: defaults
        )
        XCTAssertEqual(level, .ok)
    }

    func testBatteryUnknownSkipped() {
        // batteryLevel == -1 means we couldn't read (desktop, lid off).
        let (level, _) = SystemMonitor.evaluate(
            cpu: 10, memoryUsedGB: 1, memoryTotalGB: 32,
            diskFreeGB: 200, diskTotalGB: 500,
            batteryLevel: -1, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .ok)
    }

    // MARK: - Escalation semantics

    func testCriticalBeatsWarning() {
        // CPU critical + memory warning → overall should be critical.
        let (level, reasons) = SystemMonitor.evaluate(
            cpu: 99,
            memoryUsedGB: 27, memoryTotalGB: 32, // ~84% → warning
            diskFreeGB: 200, diskTotalGB: 500,
            batteryLevel: 80, batteryCharging: false,
            config: defaults
        )
        XCTAssertEqual(level, .critical)
        XCTAssertEqual(reasons.count, 2)
    }

    // MARK: - Config persistence

    func testConfigPersistsAcrossInstances() {
        let mon1 = SystemMonitor()
        mon1.config.cpuCrit = 77
        mon1.config.enableBattery = false
        let mon2 = SystemMonitor()
        XCTAssertEqual(mon2.config.cpuCrit, 77)
        XCTAssertFalse(mon2.config.enableBattery)
    }

    // MARK: - Tolerant decode

    func testDecodesLegacyEmptyConfig() throws {
        let data = "{}".data(using: .utf8)!
        let cfg = try JSONDecoder().decode(SystemAlertConfig.self, from: data)
        XCTAssertEqual(cfg.cpuCrit, 90)
        XCTAssertEqual(cfg.memWarn, 80)
        XCTAssertTrue(cfg.enableCPU)
    }
}
