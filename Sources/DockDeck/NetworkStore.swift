import Darwin
import Foundation
import Network
import SystemConfiguration

struct NetworkCounters: Equatable {
    let interfaceName: String
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

struct NetworkSnapshot: Equatable {
    let interfaceName: String
    let downloadBytesPerSecond: Double?
    let uploadBytesPerSecond: Double?
}

enum NetworkConnectionKind: String, Equatable {
    case wifi
    case ethernet
    case cellular
    case loopback
    case other

    var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .cellular: "Cellular"
        case .loopback: "Loopback"
        case .other: "Network"
        }
    }
}

struct NetworkConnectionSnapshot: Equatable {
    enum Status: Equatable {
        case unknown
        case online
        case offline
    }

    let status: Status
    let kind: NetworkConnectionKind?
    let isExpensive: Bool
    let isConstrained: Bool

    static let unknown = NetworkConnectionSnapshot(
        status: .unknown, kind: nil, isExpensive: false, isConstrained: false)
}

protocol NetworkPathObserving: AnyObject {
    var onUpdate: ((NetworkConnectionSnapshot) -> Void)? { get set }
    func start()
    func stop()
}

final class SystemNetworkPathObserver: NetworkPathObserving {
    var onUpdate: ((NetworkConnectionSnapshot) -> Void)?

    private let queue = DispatchQueue(label: "DockDeck.NetworkPath", qos: .utility)
    private var monitor: NWPathMonitor?

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = Self.snapshot(path)
            DispatchQueue.main.async { self?.onUpdate?(snapshot) }
        }
        self.monitor = monitor
        monitor.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    private static func snapshot(_ path: NWPath) -> NetworkConnectionSnapshot {
        let kind: NetworkConnectionKind?
        if path.usesInterfaceType(.wifi) {
            kind = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            kind = .ethernet
        } else if path.usesInterfaceType(.cellular) {
            kind = .cellular
        } else if path.usesInterfaceType(.loopback) {
            kind = .loopback
        } else if path.status == .satisfied {
            kind = .other
        } else {
            kind = nil
        }
        return NetworkConnectionSnapshot(
            status: path.status == .satisfied ? .online : .offline,
            kind: kind,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained)
    }
}

enum NetworkRateCalculator {
    static func rate(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double? {
        guard current >= previous, elapsed > 0, elapsed.isFinite else { return nil }
        let value = Double(current - previous) / elapsed
        guard value.isFinite, value <= 100 * 1_000_000_000 else { return nil }
        return value
    }
}

enum ByteRateFormatter {
    static func string(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond, value.isFinite, value >= 0 else { return "--" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var scaled = value
        var index = 0
        while scaled >= 1_024, index < units.count - 1 {
            scaled /= 1_024
            index += 1
        }
        let precision = scaled >= 100 || index == 0 ? 0 : scaled >= 10 ? 1 : 2
        return String(format: "%.*f %@", precision, scaled, units[index])
    }

    static func compactString(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond, value.isFinite, value >= 0 else { return "--" }
        let units = ["B", "K", "M", "G"]
        var scaled = value
        var index = 0
        while scaled >= 1_024, index < units.count - 1 {
            scaled /= 1_024
            index += 1
        }
        let precision = scaled >= 100 || index == 0 ? 0 : 1
        return String(format: "%.*f%@", precision, scaled, units[index])
    }
}

enum NetworkCounterReader {
    static func normalizedInterfaceName(_ value: String) -> String {
        guard value.utf8.count < Int(IFNAMSIZ),
            value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                || (97...122).contains($0) || [45, 46, 95].contains($0) })
        else { return "" }
        return value
    }

    static func availableInterfaces() -> [String] {
        guard let interfaces = if_nameindex() else { return [] }
        defer { if_freenameindex(interfaces) }
        var names: [String] = []
        var index = 0
        while interfaces[index].if_index != 0, let name = interfaces[index].if_name {
            names.append(String(cString: name))
            index += 1
        }
        return names.sorted()
    }

    static func read(interfaceName selectedInterface: String? = nil) -> NetworkCounters? {
        guard let interfaceName = selectedInterface ?? primaryInterfaceName() else { return nil }
        let index = if_nametoindex(interfaceName)
        guard index != 0 else { return nil }

        var managementInformationBase = [
            Int32(CTL_NET), Int32(PF_ROUTE), 0, 0, Int32(NET_RT_IFLIST2), 0,
        ]
        var length = 0
        guard
            sysctl(
                &managementInformationBase,
                u_int(managementInformationBase.count), nil, &length, nil, 0) == 0,
            length >= MemoryLayout<if_msghdr2>.size
        else { return nil }

        var bytes = [UInt8](repeating: 0, count: length)
        let result = bytes.withUnsafeMutableBytes { buffer in
            sysctl(
                &managementInformationBase,
                u_int(managementInformationBase.count), buffer.baseAddress, &length, nil, 0)
        }
        guard result == 0, length <= bytes.count else { return nil }

        return bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset + 4 <= length {
                let messageLength = Int(
                    buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength >= 4, offset + messageLength <= length else { return nil }
                let messageType = buffer[offset + 3]
                if messageType == UInt8(RTM_IFINFO2),
                    messageLength >= MemoryLayout<if_msghdr2>.size
                {
                    let message = buffer.loadUnaligned(
                        fromByteOffset: offset, as: if_msghdr2.self)
                    if UInt32(message.ifm_index) == index {
                        return NetworkCounters(
                            interfaceName: interfaceName,
                            receivedBytes: message.ifm_data.ifi_ibytes,
                            sentBytes: message.ifm_data.ifi_obytes)
                    }
                }
                offset += messageLength
            }
            return nil
        }
    }

    private static func primaryInterfaceName() -> String? {
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            guard
                let values = SCDynamicStoreCopyValue(nil, key as CFString)
                    as? [String: Any],
                let name = values[kSCDynamicStorePropNetPrimaryInterface as String]
                    as? String,
                !name.isEmpty
            else { continue }
            return name
        }
        return nil
    }
}

final class NetworkStore: ObservableObject {
    @Published private(set) var snapshot: NetworkSnapshot?
    @Published private(set) var connection: NetworkConnectionSnapshot
    private(set) var downloadHistory = MetricHistory()
    private(set) var uploadHistory = MetricHistory()

    private(set) var observedAt: Date?
    private(set) var interfaceName: String
    private let counterReader: (String?) -> NetworkCounters?
    private var historyInterfaceName: String?
    private var previous: (counters: NetworkCounters, date: Date)?
    private var timer: Timer?
    private var refreshInterval: TimeInterval
    private var refreshCadence = ModuleRefreshCadence(backgroundMultiplier: 4)
    private var runtimeLowPowerMode = false
    private let pathObserver: NetworkPathObserving

    init(
        refreshInterval: TimeInterval = PanelSettings.networkRefreshInterval,
        initialSnapshot: NetworkSnapshot? = nil,
        initialConnection: NetworkConnectionSnapshot = .unknown,
        pathObserver: NetworkPathObserving = SystemNetworkPathObserver(),
        interfaceName: String = PanelSettings.networkInterfaceName,
        counterReader: @escaping (String?) -> NetworkCounters? = NetworkCounterReader.read(interfaceName:)
    ) {
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
        snapshot = initialSnapshot
        connection = initialConnection
        self.pathObserver = pathObserver
        self.interfaceName = NetworkCounterReader.normalizedInterfaceName(interfaceName)
        self.counterReader = counterReader
        pathObserver.onUpdate = { [weak self] in self?.receiveConnection($0) }
    }

    func start() {
        guard timer == nil else { return }
        pathObserver.start()
        refresh()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previous = nil
        pathObserver.stop()
    }

    var measurementStatus: String {
        if snapshot == nil {
            return interfaceName.isEmpty && connection.status == .offline
                ? "Network offline" : "Counters unavailable"
        }
        return snapshot?.downloadBytesPerSecond == nil ? "Measuring rate" : "Live counters"
    }

    func setInterfaceName(_ value: String) {
        let value = NetworkCounterReader.normalizedInterfaceName(value)
        guard interfaceName != value else { return }
        interfaceName = value
        previous = nil
        downloadHistory = MetricHistory()
        uploadHistory = MetricHistory()
        observedAt = nil
        snapshot = nil
        if timer != nil { refresh() }
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        let interval = Self.resolvedRefreshInterval(interval)
        guard refreshInterval != interval else { return }
        refreshInterval = interval
        guard timer != nil else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    func setRuntimeActivity(
        _ activity: ModuleRuntimeActivity, lowPowerMode: Bool
    ) {
        runtimeLowPowerMode = lowPowerMode
        guard refreshCadence.update(
            activity: activity,
            lowPowerMode: lowPowerMode || connection.isConstrained),
            timer != nil
        else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    func refresh(now: Date = Date()) {
        guard let counters = counterReader(interfaceName.isEmpty ? nil : interfaceName) else {
            previous = nil
            snapshot = nil
            return
        }
        if historyInterfaceName != counters.interfaceName {
            downloadHistory = MetricHistory()
            uploadHistory = MetricHistory()
            historyInterfaceName = counters.interfaceName
        }
        let rates: (download: Double?, upload: Double?)
        if let previous, previous.counters.interfaceName == counters.interfaceName {
            let elapsed = now.timeIntervalSince(previous.date)
            rates = (
                NetworkRateCalculator.rate(
                    previous: previous.counters.receivedBytes,
                    current: counters.receivedBytes,
                    elapsed: elapsed),
                NetworkRateCalculator.rate(
                    previous: previous.counters.sentBytes,
                    current: counters.sentBytes,
                    elapsed: elapsed))
        } else {
            rates = (nil, nil)
        }
        previous = (counters, now)
        downloadHistory.append(rates.download, at: now)
        uploadHistory.append(rates.upload, at: now)
        observedAt = now
        snapshot = NetworkSnapshot(
            interfaceName: counters.interfaceName,
            downloadBytesPerSecond: rates.download,
            uploadBytesPerSecond: rates.upload)
    }

    private func receiveConnection(_ connection: NetworkConnectionSnapshot) {
        guard self.connection != connection else { return }
        self.connection = connection
        guard refreshCadence.update(
            activity: refreshCadence.activity,
            lowPowerMode: runtimeLowPowerMode || connection.isConstrained),
            timer != nil
        else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    private func scheduleTimer() {
        let interval = refreshCadence.effectiveInterval(
            configuredInterval: refreshInterval)
        timer = .moduleRefreshTimer(interval: interval) { [weak self] in self?.refresh() }
    }

    private static func resolvedRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        PanelSettings.networkRefreshIntervals.min(by: {
            abs($0 - interval) < abs($1 - interval)
        }) ?? PanelSettings.defaultNetworkRefreshInterval
    }
}
