import Foundation

enum ModuleRuntimeActivity: Equatable {
    case background
    case visible
}

struct ModuleRefreshCadence: Equatable {
    private(set) var activity: ModuleRuntimeActivity
    private(set) var lowPowerMode: Bool
    let backgroundMultiplier: Double
    let lowPowerMultiplier: Double

    init(
        activity: ModuleRuntimeActivity = .visible,
        lowPowerMode: Bool = false,
        backgroundMultiplier: Double = 1,
        lowPowerMultiplier: Double = 2
    ) {
        self.activity = activity
        self.lowPowerMode = lowPowerMode
        self.backgroundMultiplier = max(backgroundMultiplier, 1)
        self.lowPowerMultiplier = max(lowPowerMultiplier, 1)
    }

    mutating func update(
        activity: ModuleRuntimeActivity, lowPowerMode: Bool
    ) -> Bool {
        guard self.activity != activity || self.lowPowerMode != lowPowerMode else {
            return false
        }
        self.activity = activity
        self.lowPowerMode = lowPowerMode
        return true
    }

    func effectiveInterval(configuredInterval: TimeInterval) -> TimeInterval {
        let background = activity == .background ? backgroundMultiplier : 1
        let power = lowPowerMode ? lowPowerMultiplier : 1
        return max(configuredInterval * background * power, 0.1)
    }
}

extension Timer {
    /// Repeating main-run-loop timer with 10% tolerance so macOS can coalesce module
    /// wakeups. Rate math in the stores uses measured elapsed time, not this interval.
    static func moduleRefreshTimer(
        interval: TimeInterval, _ handler: @escaping () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in handler() }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

protocol PanelModuleRuntime: AnyObject {
    func start()
    func stop()
    func setRuntimeActivity(_ activity: ModuleRuntimeActivity, lowPowerMode: Bool)
}

extension PanelModuleRuntime {
    func setRuntimeActivity(_ activity: ModuleRuntimeActivity, lowPowerMode: Bool) {}
}

extension UsageStore: PanelModuleRuntime {}
extension SystemStatsStore: PanelModuleRuntime {}
extension ServiceMonitorStore: PanelModuleRuntime {}
extension WeatherStore: PanelModuleRuntime {}
extension ScheduleStore: PanelModuleRuntime {}
extension ClockStore: PanelModuleRuntime {}
extension BatteryStore: PanelModuleRuntime {}
extension NetworkStore: PanelModuleRuntime {}
extension ProjectPulseStore: PanelModuleRuntime {}
extension GitHubInboxStore: PanelModuleRuntime {}
extension FocusTimerStore: PanelModuleRuntime {}

final class ModuleRuntimeCoordinator {
    enum State: Equatable {
        case stopped
        case background
        case visible

        var activity: ModuleRuntimeActivity? {
            switch self {
            case .stopped: nil
            case .background: .background
            case .visible: .visible
            }
        }
    }

    private struct Runtime {
        let start: () -> Void
        let stop: () -> Void
        let updateActivity: (ModuleRuntimeActivity, Bool) -> Void
    }

    private var runtimes: [PanelModuleID: Runtime] = [:]
    private var states: [PanelModuleID: State] = [:]
    private var lowPowerMode = false

    func register(
        _ module: PanelModuleID,
        start: @escaping () -> Void,
        stop: @escaping () -> Void,
        updateActivity: @escaping (ModuleRuntimeActivity, Bool) -> Void = { _, _ in }
    ) {
        precondition(runtimes[module] == nil, "Module runtime registered twice: \(module.rawValue)")
        runtimes[module] = Runtime(
            start: start, stop: stop, updateActivity: updateActivity)
        states[module] = .stopped
    }

    func synchronize(
        enabledModules: [PanelModuleID],
        visibleModules: [PanelModuleID] = [],
        lowPowerMode: Bool = false
    ) {
        let enabledModules = Set(enabledModules).intersection(Set(runtimes.keys))
        let visibleModules = Set(visibleModules).intersection(enabledModules)

        for (module, runtime) in runtimes {
            let previous = states[module] ?? .stopped
            let next: State
            if !enabledModules.contains(module) {
                next = .stopped
            } else if visibleModules.contains(module) {
                next = .visible
            } else {
                next = .background
            }

            if let activity = next.activity,
                previous != next || self.lowPowerMode != lowPowerMode
            {
                runtime.updateActivity(activity, lowPowerMode)
            }
            if previous == .stopped, next != .stopped {
                runtime.start()
            } else if previous != .stopped, next == .stopped {
                runtime.stop()
            }
            states[module] = next
        }
        self.lowPowerMode = lowPowerMode
    }

    func stopAll() {
        for (module, runtime) in runtimes where states[module] != .stopped {
            runtime.stop()
            states[module] = .stopped
        }
    }

    func state(for module: PanelModuleID) -> State {
        states[module] ?? .stopped
    }
}
