import Darwin
import Foundation

struct CPUCounters: Equatable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var total: UInt64 { user + system + idle + nice }
}

struct SystemStatsSnapshot: Equatable {
    var cpuPercent: Double?
    var memoryPercent: Double?
    var diskPercent: Double?

    static let empty = SystemStatsSnapshot()
}

enum SystemStatsCalculator {
    static func cpuPercent(previous: CPUCounters, current: CPUCounters) -> Double? {
        guard current.total >= previous.total, current.idle >= previous.idle else { return nil }
        let totalDelta = current.total - previous.total
        guard totalDelta > 0 else { return nil }
        let idleDelta = current.idle - previous.idle
        return boundedPercent(used: totalDelta - min(idleDelta, totalDelta), total: totalDelta)
    }

    static func boundedPercent(used: UInt64, total: UInt64) -> Double? {
        guard total > 0 else { return nil }
        return min(max(Double(used) / Double(total) * 100, 0), 100)
    }
}

private struct SystemStatsReading {
    let cpu: CPUCounters?
    let memoryUsed: UInt64?
    let memoryTotal: UInt64?
    let diskUsed: UInt64?
    let diskTotal: UInt64?
}

final class SystemStatsStore: ObservableObject {
    @Published private(set) var snapshot = SystemStatsSnapshot.empty

    private var timer: Timer?
    private var previousCPU: CPUCounters?
    private var refreshInterval: TimeInterval

    init(
        refreshInterval: TimeInterval = PanelSettings.systemStatsRefreshInterval,
        initialSnapshot: SystemStatsSnapshot = .empty
    ) {
        self.refreshInterval = refreshInterval
        snapshot = initialSnapshot
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousCPU = nil
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard refreshInterval != interval else { return }
        refreshInterval = interval
        guard timer != nil else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    func refresh() {
        let reading = Self.readSystemStats()
        let cpuPercent = previousCPU.flatMap { previous in
            reading.cpu.flatMap { SystemStatsCalculator.cpuPercent(previous: previous, current: $0) }
        }
        previousCPU = reading.cpu
        snapshot = SystemStatsSnapshot(
            cpuPercent: cpuPercent ?? snapshot.cpuPercent,
            memoryPercent: Self.percent(used: reading.memoryUsed, total: reading.memoryTotal),
            diskPercent: Self.percent(used: reading.diskUsed, total: reading.diskTotal))
    }

    private func scheduleTimer() {
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func percent(used: UInt64?, total: UInt64?) -> Double? {
        guard let used, let total else { return nil }
        return SystemStatsCalculator.boundedPercent(used: used, total: total)
    }

    private static func readSystemStats() -> SystemStatsReading {
        let memory = readMemory()
        let disk = readDisk()
        return SystemStatsReading(
            cpu: readCPU(),
            memoryUsed: memory?.used,
            memoryTotal: memory?.total,
            diskUsed: disk?.used,
            diskTotal: disk?.total)
    }

    private static func readCPU() -> CPUCounters? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = withUnsafeBytes(of: info.cpu_ticks) {
            Array($0.bindMemory(to: UInt32.self))
        }
        guard ticks.count >= Int(CPU_STATE_MAX) else { return nil }
        return CPUCounters(
            user: UInt64(ticks[Int(CPU_STATE_USER)]),
            system: UInt64(ticks[Int(CPU_STATE_SYSTEM)]),
            idle: UInt64(ticks[Int(CPU_STATE_IDLE)]),
            nice: UInt64(ticks[Int(CPU_STATE_NICE)]))
    }

    private static func readMemory() -> (used: UInt64, total: UInt64)? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let usedPages = UInt64(info.active_count) + UInt64(info.inactive_count)
            + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        return (usedPages * UInt64(pageSize), ProcessInfo.processInfo.physicalMemory)
    }

    private static func readDisk() -> (used: UInt64, total: UInt64)? {
        guard
            let attributes = try? FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory()),
            let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
            let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value,
            total >= free
        else { return nil }
        return (total - free, total)
    }
}
