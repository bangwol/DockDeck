import Foundation

enum ModuleRuntimePolicy {
    static func isConstrained(
        lowPowerMode: Bool, thermalState: ProcessInfo.ThermalState
    ) -> Bool {
        if lowPowerMode { return true }
        switch thermalState {
        case .serious, .critical: return true
        case .nominal, .fair: return false
        @unknown default: return true
        }
    }
}

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
extension DockerStore: PanelModuleRuntime {}
extension CustomTileStore: PanelModuleRuntime {}
extension FocusTimerStore: PanelModuleRuntime {}

struct ModuleRuntimeDiagnostics: Equatable {
    let states: [PanelModuleID: ModuleRuntimeCoordinator.State]
    let stateChangedAt: [PanelModuleID: Date]
    let systemActive: Bool
    let constrained: Bool

    init(
        states: [PanelModuleID: ModuleRuntimeCoordinator.State],
        systemActive: Bool,
        constrained: Bool,
        stateChangedAt: [PanelModuleID: Date] = [:]
    ) {
        self.states = states
        self.stateChangedAt = stateChangedAt
        self.systemActive = systemActive
        self.constrained = constrained
    }

    static let empty = ModuleRuntimeDiagnostics(
        states: [:], systemActive: true, constrained: false)
}

final class ModuleRuntimeCoordinator {
    enum State: Equatable {
        case stopped
        case suspended
        case background
        case visible

        var activity: ModuleRuntimeActivity? {
            switch self {
            case .stopped, .suspended: nil
            case .background: .background
            case .visible: .visible
            }
        }

        var isRunning: Bool { activity != nil }
    }

    private struct Runtime {
        let start: () -> Void
        let stop: () -> Void
        let updateActivity: (ModuleRuntimeActivity, Bool) -> Void
        let suspendsWhenInactive: Bool
    }

    private var runtimes: [PanelModuleID: Runtime] = [:]
    private var states: [PanelModuleID: State] = [:]
    private var stateChangedAt: [PanelModuleID: Date] = [:]
    private var lowPowerMode = false
    private var systemActive = true
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func register(
        _ module: PanelModuleID,
        start: @escaping () -> Void,
        stop: @escaping () -> Void,
        suspendsWhenInactive: Bool = true,
        updateActivity: @escaping (ModuleRuntimeActivity, Bool) -> Void = { _, _ in }
    ) {
        precondition(runtimes[module] == nil, "Module runtime registered twice: \(module.rawValue)")
        runtimes[module] = Runtime(
            start: start, stop: stop, updateActivity: updateActivity,
            suspendsWhenInactive: suspendsWhenInactive)
        states[module] = .stopped
        stateChangedAt[module] = now()
    }

    func synchronize(
        enabledModules: [PanelModuleID],
        visibleModules: [PanelModuleID] = [],
        lowPowerMode: Bool = false,
        systemActive: Bool = true
    ) {
        let registeredModules = Set(runtimes.keys)
        let enabledSet = Set(enabledModules).intersection(registeredModules)
        let visibleSet = Set(visibleModules).intersection(enabledSet)
        let previousStates = states
        var nextStates: [PanelModuleID: State] = [:]

        for (module, runtime) in runtimes {
            let next: State
            if !enabledSet.contains(module) {
                next = .stopped
            } else if !systemActive, runtime.suspendsWhenInactive {
                next = .suspended
            } else if visibleSet.contains(module) {
                next = .visible
            } else {
                next = .background
            }
            nextStates[module] = next
        }

        // Stop inactive work before starting anything else. The interactive terminal opts out
        // so its shell survives display sleep and fast-user switching.
        for (module, runtime) in runtimes {
            let previous = states[module] ?? .stopped
            let next = nextStates[module] ?? .stopped
            if previous.isRunning, !next.isRunning { runtime.stop() }
            if previous != next { stateChangedAt[module] = now() }
            states[module] = next
        }

        // Preserve deck order and start visible modules first after wake. This avoids a burst
        // of hidden network and CLI work delaying the information currently on screen.
        var activated: Set<PanelModuleID> = []
        let activationOrder = (visibleModules + enabledModules).filter {
            enabledSet.contains($0) && activated.insert($0).inserted
        }
        for module in activationOrder {
            guard let runtime = runtimes[module], let next = nextStates[module],
                let activity = next.activity
            else { continue }
            let previous = previousStates[module] ?? .stopped
            if previous != next || self.lowPowerMode != lowPowerMode {
                runtime.updateActivity(activity, lowPowerMode)
            }
            if !previous.isRunning { runtime.start() }
        }
        self.lowPowerMode = lowPowerMode
        self.systemActive = systemActive
    }

    func stopAll() {
        for (module, runtime) in runtimes where states[module]?.isRunning == true {
            runtime.stop()
            states[module] = .stopped
            stateChangedAt[module] = now()
        }
        for module in runtimes.keys where states[module] == .suspended {
            states[module] = .stopped
            stateChangedAt[module] = now()
        }
    }

    func state(for module: PanelModuleID) -> State {
        states[module] ?? .stopped
    }

    func diagnostics() -> ModuleRuntimeDiagnostics {
        ModuleRuntimeDiagnostics(
            states: states, systemActive: systemActive, constrained: lowPowerMode,
            stateChangedAt: stateChangedAt)
    }
}
