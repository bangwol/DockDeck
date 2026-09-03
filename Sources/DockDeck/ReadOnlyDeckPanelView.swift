import SwiftUI

final class PanelModuleServices {
    let usage: UsageStore
    let systemStats: SystemStatsStore
    let serviceMonitor: ServiceMonitorStore
    let weather: WeatherStore
    let schedule: ScheduleStore
    let clock: ClockStore
    let battery: BatteryStore
    let network: NetworkStore
    let projectPulse: ProjectPulseStore
    let focusTimer: FocusTimerStore

    private let runtimes: [PanelModuleID: any PanelModuleRuntime]

    init(
        usage: UsageStore = UsageStore(),
        systemStats: SystemStatsStore = SystemStatsStore(),
        serviceMonitor: ServiceMonitorStore = ServiceMonitorStore(),
        weather: WeatherStore = WeatherStore(),
        schedule: ScheduleStore = ScheduleStore(),
        clock: ClockStore = ClockStore(),
        battery: BatteryStore = BatteryStore(),
        network: NetworkStore = NetworkStore(),
        projectPulse: ProjectPulseStore = ProjectPulseStore(),
        focusTimer: FocusTimerStore = FocusTimerStore()
    ) {
        self.usage = usage
        self.systemStats = systemStats
        self.serviceMonitor = serviceMonitor
        self.weather = weather
        self.schedule = schedule
        self.clock = clock
        self.battery = battery
        self.network = network
        self.projectPulse = projectPulse
        self.focusTimer = focusTimer
        runtimes = [
            .usage: usage,
            .systemStats: systemStats,
            .serviceMonitor: serviceMonitor,
            .weather: weather,
            .schedule: schedule,
            .clock: clock,
            .battery: battery,
            .network: network,
            .projectPulse: projectPulse,
            .focusTimer: focusTimer,
        ]
    }

    func runtime(for module: PanelModuleID) -> (any PanelModuleRuntime)? {
        runtimes[module]
    }
}

enum ReadOnlyDeckSelection {
    static func resolved(
        preferred: PanelModuleID?, enabledModules: [PanelModuleID]
    ) -> PanelModuleID? {
        if let preferred, enabledModules.contains(preferred) { return preferred }
        return enabledModules.first
    }

    static func next(
        after current: PanelModuleID?, enabledModules: [PanelModuleID]
    ) -> PanelModuleID? {
        guard !enabledModules.isEmpty else { return nil }
        guard let current, let index = enabledModules.firstIndex(of: current) else {
            return enabledModules.first
        }
        return enabledModules[(index + 1) % enabledModules.count]
    }

    static func previous(
        before current: PanelModuleID?, enabledModules: [PanelModuleID]
    ) -> PanelModuleID? {
        guard !enabledModules.isEmpty else { return nil }
        guard let current, let index = enabledModules.firstIndex(of: current) else {
            return enabledModules.last
        }
        return enabledModules[(index - 1 + enabledModules.count) % enabledModules.count]
    }
}

struct ReadOnlyDeckPanelView: View {
    let services: PanelModuleServices
    let activeModule: PanelModuleID?
    let theme: Theme

    @ViewBuilder var body: some View {
        switch activeModule {
        case .usage:
            QuotaPanelView(store: services.usage, theme: theme, configuration: .current)
        case .systemStats:
            SystemStatsPanelView(store: services.systemStats, theme: theme)
        case .serviceMonitor:
            ServiceMonitorPanelView(store: services.serviceMonitor, theme: theme)
        case .weather:
            WeatherPanelView(store: services.weather, theme: theme)
        case .schedule:
            SchedulePanelView(store: services.schedule, theme: theme)
        case .clock:
            ClockPanelView(
                store: services.clock,
                theme: theme,
                timeZoneIdentifier: PanelSettings.clockTimeZoneIdentifier,
                hourFormat: PanelSettings.clockHourFormat)
        case .battery:
            BatteryPanelView(store: services.battery, theme: theme)
        case .network:
            NetworkPanelView(store: services.network, theme: theme)
        case .projectPulse:
            ProjectPulsePanelView(store: services.projectPulse, theme: theme)
        case .focusTimer:
            FocusTimerPanelView(store: services.focusTimer, theme: theme)
        default:
            EmptyView()
        }
    }
}
