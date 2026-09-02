import Darwin
import Foundation
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
    static func read() -> NetworkCounters? {
        guard let interfaceName = primaryInterfaceName() else { return nil }
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

    private var previous: (counters: NetworkCounters, date: Date)?
    private var timer: Timer?
    private var refreshInterval: TimeInterval

    init(
        refreshInterval: TimeInterval = PanelSettings.networkRefreshInterval,
        initialSnapshot: NetworkSnapshot? = nil
    ) {
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
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
        previous = nil
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        let interval = Self.resolvedRefreshInterval(interval)
        guard refreshInterval != interval else { return }
        refreshInterval = interval
        guard timer != nil else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    func refresh(now: Date = Date()) {
        guard let counters = NetworkCounterReader.read() else {
            previous = nil
            snapshot = nil
            return
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
        snapshot = NetworkSnapshot(
            interfaceName: counters.interfaceName,
            downloadBytesPerSecond: rates.download,
            uploadBytesPerSecond: rates.upload)
    }

    private func scheduleTimer() {
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func resolvedRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        PanelSettings.networkRefreshIntervals.min(by: {
            abs($0 - interval) < abs($1 - interval)
        }) ?? PanelSettings.defaultNetworkRefreshInterval
    }
}
