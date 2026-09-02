import SwiftUI

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
    let usageStore: UsageStore
    let systemStatsStore: SystemStatsStore
    let serviceMonitorStore: ServiceMonitorStore
    let weatherStore: WeatherStore
    let scheduleStore: ScheduleStore
    let clockStore: ClockStore
    let batteryStore: BatteryStore
    let networkStore: NetworkStore
    let activeModule: PanelModuleID?
    let theme: Theme

    @ViewBuilder var body: some View {
        switch activeModule {
        case .usage:
            QuotaPanelView(store: usageStore, theme: theme, configuration: .current)
        case .systemStats:
            SystemStatsPanelView(store: systemStatsStore, theme: theme)
        case .serviceMonitor:
            ServiceMonitorPanelView(store: serviceMonitorStore, theme: theme)
        case .weather:
            WeatherPanelView(store: weatherStore, theme: theme)
        case .schedule:
            SchedulePanelView(store: scheduleStore, theme: theme)
        case .clock:
            ClockPanelView(
                store: clockStore,
                theme: theme,
                timeZoneIdentifier: PanelSettings.clockTimeZoneIdentifier,
                hourFormat: PanelSettings.clockHourFormat)
        case .battery:
            BatteryPanelView(store: batteryStore, theme: theme)
        case .network:
            NetworkPanelView(store: networkStore, theme: theme)
        default:
            EmptyView()
        }
    }
}
