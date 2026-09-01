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
}

struct ReadOnlyDeckPanelView: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var systemStatsStore: SystemStatsStore
    @ObservedObject var serviceMonitorStore: ServiceMonitorStore
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
        default:
            EmptyView()
        }
    }
}
