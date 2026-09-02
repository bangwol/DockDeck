import Darwin
import Foundation

enum SystemStatsMetric: String, CaseIterable, Codable, Identifiable {
    case cpu
    case memory
    case disk
    case network
    case thermal

    static let minimumSelectionCount = 2
    static let maximumSelectionCount = 4
    static let defaultSelection: [Self] = [.cpu, .memory, .disk, .network]

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network I/O"
        case .thermal: "Temperature"
        }
    }

    var compactTitle: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "MEM"
        case .disk: "DISK"
        case .network: "NET"
        case .thermal: "TEMP"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .thermal: "thermometer.medium"
        }
    }

    static func normalized(_ metrics: [Self]) -> [Self] {
        guard !metrics.isEmpty else { return defaultSelection }
        let requested = Set(metrics)
        var result = Array(allCases.filter(requested.contains).prefix(maximumSelectionCount))
        for metric in defaultSelection
            where result.count < minimumSelectionCount && !result.contains(metric)
        {
            result.append(metric)
        }
        let selected = Set(result)
        return allCases.filter(selected.contains)
    }
}

struct CPUCounters: Equatable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var total: UInt64 { user + system + idle + nice }
}

enum SystemThermalPressure: String, Equatable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    var level: Double {
        switch self {
        case .nominal: 0.25
        case .fair: 0.5
        case .serious: 0.75
        case .critical: 1
        }
    }
}

struct SystemStatsSnapshot: Equatable {
    var cpuPercent: Double?
    var memoryPercent: Double?
    var diskPercent: Double?
    var downloadBytesPerSecond: Double?
    var uploadBytesPerSecond: Double?
    var temperatureCelsius: Double?
    var thermalPressure: SystemThermalPressure?

    static let empty = SystemStatsSnapshot()

    init(
        cpuPercent: Double? = nil,
        memoryPercent: Double? = nil,
        diskPercent: Double? = nil,
        downloadBytesPerSecond: Double? = nil,
        uploadBytesPerSecond: Double? = nil,
        temperatureCelsius: Double? = nil,
        thermalPressure: SystemThermalPressure? = nil
    ) {
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.diskPercent = diskPercent
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.temperatureCelsius = temperatureCelsius
        self.thermalPressure = thermalPressure
    }
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

    static func activityMonitorMemoryUsedPages(
        internalPages: UInt64,
        wiredPages: UInt64,
        compressorPages: UInt64
    ) -> UInt64 {
        internalPages + wiredPages + compressorPages
    }
}

private struct SystemStatsReading {
    let cpu: CPUCounters?
    let memoryUsed: UInt64?
    let memoryTotal: UInt64?
    let diskUsed: UInt64?
    let diskTotal: UInt64?
    let network: NetworkCounters?
    let thermalPressure: SystemThermalPressure?
}

final class SystemStatsStore: ObservableObject {
    private static let temperatureRefreshInterval: TimeInterval = 15

    @Published private(set) var snapshot: SystemStatsSnapshot
    @Published private(set) var selectedMetrics: [SystemStatsMetric]

    private var timer: Timer?
    private var previousCPU: CPUCounters?
    private var previousNetwork: (counters: NetworkCounters, date: Date)?
    private var cachedTemperatureCelsius: Double?
    private var lastTemperatureAttempt: Date?
    private var temperatureReadInFlight = false
    private var temperatureReadGeneration = 0
    private var refreshInterval: TimeInterval
    private var refreshCadence = ModuleRefreshCadence(backgroundMultiplier: 4)

    init(
        refreshInterval: TimeInterval = PanelSettings.systemStatsRefreshInterval,
        metrics: [SystemStatsMetric] = PanelSettings.systemStatsMetrics,
        initialSnapshot: SystemStatsSnapshot = .empty
    ) {
        self.refreshInterval = refreshInterval
        selectedMetrics = SystemStatsMetric.normalized(metrics)
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
        previousNetwork = nil
        resetTemperatureSampling()
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard refreshInterval != interval else { return }
        refreshInterval = interval
        guard timer != nil else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    func setRuntimeActivity(
        _ activity: ModuleRuntimeActivity, lowPowerMode: Bool
    ) {
        guard refreshCadence.update(activity: activity, lowPowerMode: lowPowerMode),
            timer != nil
        else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    func setMetrics(_ metrics: [SystemStatsMetric]) {
        let metrics = SystemStatsMetric.normalized(metrics)
        guard selectedMetrics != metrics else { return }
        let hadTemperature = selectedMetrics.contains(.thermal)
        selectedMetrics = metrics
        if !metrics.contains(.cpu) { previousCPU = nil }
        if !metrics.contains(.network) { previousNetwork = nil }
        if !metrics.contains(.thermal) || !hadTemperature { resetTemperatureSampling() }
        if timer != nil { refresh() }
    }

    func refresh(now: Date = Date()) {
        let metrics = Set(selectedMetrics)
        let reading = Self.readSystemStats(metrics: metrics)

        let cpuPercent = previousCPU.flatMap { previous in
            reading.cpu.flatMap { SystemStatsCalculator.cpuPercent(previous: previous, current: $0) }
        }
        previousCPU = reading.cpu

        let networkRates = Self.networkRates(
            previous: previousNetwork, current: reading.network, now: now)
        previousNetwork = reading.network.map { (counters: $0, date: now) }

        snapshot = SystemStatsSnapshot(
            cpuPercent: metrics.contains(.cpu) ? cpuPercent ?? snapshot.cpuPercent : nil,
            memoryPercent: metrics.contains(.memory)
                ? Self.percent(used: reading.memoryUsed, total: reading.memoryTotal) : nil,
            diskPercent: metrics.contains(.disk)
                ? Self.percent(used: reading.diskUsed, total: reading.diskTotal) : nil,
            downloadBytesPerSecond: metrics.contains(.network) ? networkRates.download : nil,
            uploadBytesPerSecond: metrics.contains(.network) ? networkRates.upload : nil,
            temperatureCelsius: metrics.contains(.thermal) ? cachedTemperatureCelsius : nil,
            thermalPressure: metrics.contains(.thermal) ? reading.thermalPressure : nil)
        if metrics.contains(.thermal) { refreshTemperatureIfNeeded(now: now) }
    }

    private func scheduleTimer() {
        let interval = refreshCadence.effectiveInterval(
            configuredInterval: refreshInterval)
        timer = .moduleRefreshTimer(interval: interval) { [weak self] in self?.refresh() }
    }

    private static func percent(used: UInt64?, total: UInt64?) -> Double? {
        guard let used, let total else { return nil }
        return SystemStatsCalculator.boundedPercent(used: used, total: total)
    }

    private func refreshTemperatureIfNeeded(now: Date) {
        guard InstalledTemperatureReader.isAvailable, !temperatureReadInFlight,
            lastTemperatureAttempt.map({
                now.timeIntervalSince($0) >= Self.temperatureRefreshInterval
            }) ?? true
        else { return }

        lastTemperatureAttempt = now
        temperatureReadInFlight = true
        let generation = temperatureReadGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let value = InstalledTemperatureReader.readHottestCPUCelsius()
            DispatchQueue.main.async {
                guard let self, self.temperatureReadGeneration == generation else { return }
                self.temperatureReadInFlight = false
                self.cachedTemperatureCelsius = value
                guard self.selectedMetrics.contains(.thermal) else { return }
                var snapshot = self.snapshot
                snapshot.temperatureCelsius = value
                self.snapshot = snapshot
            }
        }
    }

    private func resetTemperatureSampling() {
        temperatureReadGeneration += 1
        temperatureReadInFlight = false
        cachedTemperatureCelsius = nil
        lastTemperatureAttempt = nil
        snapshot.temperatureCelsius = nil
    }

    private static func networkRates(
        previous: (counters: NetworkCounters, date: Date)?,
        current: NetworkCounters?,
        now: Date
    ) -> (download: Double?, upload: Double?) {
        guard let previous, let current,
            previous.counters.interfaceName == current.interfaceName
        else { return (nil, nil) }
        let elapsed = now.timeIntervalSince(previous.date)
        return (
            NetworkRateCalculator.rate(
                previous: previous.counters.receivedBytes,
                current: current.receivedBytes,
                elapsed: elapsed),
            NetworkRateCalculator.rate(
                previous: previous.counters.sentBytes,
                current: current.sentBytes,
                elapsed: elapsed))
    }

    private static func readSystemStats(metrics: Set<SystemStatsMetric>) -> SystemStatsReading {
        let memory = metrics.contains(.memory) ? readMemory() : nil
        let disk = metrics.contains(.disk) ? readDisk() : nil
        return SystemStatsReading(
            cpu: metrics.contains(.cpu) ? readCPU() : nil,
            memoryUsed: memory?.used,
            memoryTotal: memory?.total,
            diskUsed: disk?.used,
            diskTotal: disk?.total,
            network: metrics.contains(.network) ? NetworkCounterReader.read() : nil,
            thermalPressure: metrics.contains(.thermal)
                ? SystemThermalPressure(ProcessInfo.processInfo.thermalState) : nil)
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
        let usedPages = SystemStatsCalculator.activityMonitorMemoryUsedPages(
            internalPages: UInt64(info.internal_page_count),
            wiredPages: UInt64(info.wire_count),
            compressorPages: UInt64(info.compressor_page_count))
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
