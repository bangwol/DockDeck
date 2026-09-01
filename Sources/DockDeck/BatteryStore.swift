import Foundation
import IOKit.ps

enum BatteryChargeState: Equatable {
    case charging
    case charged
    case discharging
    case connected

    var title: String {
        switch self {
        case .charging: "Charging"
        case .charged: "Charged"
        case .discharging: "On Battery"
        case .connected: "On Power"
        }
    }
}

struct BatterySnapshot: Equatable {
    let percent: Double
    let state: BatteryChargeState
    let minutesRemaining: Int?
}

enum BatteryCalculator {
    static func percent(current: Int, maximum: Int) -> Double? {
        guard current >= 0, maximum > 0 else { return nil }
        return min(max(Double(current) / Double(maximum) * 100, 0), 100)
    }

    static func minutesRemaining(_ value: Any?) -> Int? {
        guard let minutes = (value as? NSNumber)?.intValue,
            (1...(7 * 24 * 60)).contains(minutes)
        else { return nil }
        return minutes
    }
}

enum BatteryReader {
    static func read() -> BatterySnapshot? {
        guard let informationReference = IOPSCopyPowerSourcesInfo() else { return nil }
        let information = informationReference.takeRetainedValue()
        guard let sourcesReference = IOPSCopyPowerSourcesList(information) else { return nil }
        let sources = sourcesReference.takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard
                let descriptionReference = IOPSGetPowerSourceDescription(information, source),
                let description = descriptionReference.takeUnretainedValue()
                    as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue,
                let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.intValue,
                let percent = BatteryCalculator.percent(current: current, maximum: maximum)
            else { continue }
            if let isPresent = description[kIOPSIsPresentKey] as? NSNumber,
                !isPresent.boolValue
            {
                continue
            }

            let isCharging = (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue == true
            let isCharged = (description[kIOPSIsChargedKey] as? NSNumber)?.boolValue == true
            let sourceState = description[kIOPSPowerSourceStateKey] as? String
            let state: BatteryChargeState
            let estimate: Any?
            if isCharging {
                state = .charging
                estimate = description[kIOPSTimeToFullChargeKey]
            } else if isCharged {
                state = .charged
                estimate = nil
            } else if sourceState == kIOPSBatteryPowerValue {
                state = .discharging
                estimate = description[kIOPSTimeToEmptyKey]
            } else {
                state = .connected
                estimate = nil
            }

            return BatterySnapshot(
                percent: percent,
                state: state,
                minutesRemaining: BatteryCalculator.minutesRemaining(estimate))
        }
        return nil
    }
}

final class BatteryStore: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?

    private var timer: Timer?
    private var refreshInterval: TimeInterval

    init(
        refreshInterval: TimeInterval = PanelSettings.batteryRefreshInterval,
        initialSnapshot: BatterySnapshot? = nil
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
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        let interval = Self.resolvedRefreshInterval(interval)
        guard refreshInterval != interval else { return }
        refreshInterval = interval
        guard timer != nil else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    func refresh() {
        snapshot = BatteryReader.read()
    }

    private func scheduleTimer() {
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func resolvedRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        PanelSettings.batteryRefreshIntervals.min(by: {
            abs($0 - interval) < abs($1 - interval)
        }) ?? PanelSettings.defaultBatteryRefreshInterval
    }
}
