import SwiftUI

enum DeckTransitionDirection: Equatable {
    case previous
    case next
}

struct DeckTransitionPlan: Equatable {
    let insertionEdge: Edge
    let removalEdge: Edge

    static func resolved(
        direction: DeckTransitionDirection, reduceMotion: Bool
    ) -> Self? {
        guard !reduceMotion else { return nil }
        switch direction {
        case .previous:
            return Self(insertionEdge: .top, removalEdge: .bottom)
        case .next:
            return Self(insertionEdge: .bottom, removalEdge: .top)
        }
    }
}

final class ReadOnlyDeckPresentation: ObservableObject {
    @Published private(set) var activeModule: PanelModuleID?
    @Published private(set) var theme: Theme
    @Published private(set) var direction = DeckTransitionDirection.next
    @Published private(set) var pageIndicator: String?
    private var indicatorDismissal: DispatchWorkItem?

    init(activeModule: PanelModuleID?, theme: Theme) {
        self.activeModule = activeModule
        self.theme = theme
    }

    func setTheme(_ theme: Theme) {
        self.theme = theme
    }

    func select(
        _ module: PanelModuleID?, direction: DeckTransitionDirection,
        enabledModules: [PanelModuleID], showsIndicator: Bool
    ) {
        self.direction = direction
        activeModule = module
        indicatorDismissal?.cancel()
        guard showsIndicator, let module,
            let index = enabledModules.firstIndex(of: module), enabledModules.count > 1
        else {
            pageIndicator = nil
            return
        }
        pageIndicator = "\(index + 1)/\(enabledModules.count)"
        let dismissal = DispatchWorkItem { [weak self] in self?.pageIndicator = nil }
        indicatorDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: dismissal)
    }
}

final class PanelModuleServices {
    let usage: UsageStore
    let systemStats: SystemStatsStore
    let serviceMonitor: ServiceMonitorStore
    let weather: WeatherStore
    let schedule: ScheduleStore
    let clock: ClockStore
    let music: MusicStore
    let battery: BatteryStore
    let network: NetworkStore
    let projectPulse: ProjectPulseStore
    let githubInbox: GitHubInboxStore
    let docker: DockerStore
    let customTile: CustomTileStore
    let focusTimer: FocusTimerStore

    private let runtimes: [PanelModuleID: any PanelModuleRuntime]

    init(
        usage: UsageStore = UsageStore(),
        systemStats: SystemStatsStore = SystemStatsStore(),
        serviceMonitor: ServiceMonitorStore = ServiceMonitorStore(),
        weather: WeatherStore = WeatherStore(),
        schedule: ScheduleStore = ScheduleStore(),
        clock: ClockStore = ClockStore(),
        music: MusicStore = MusicStore(),
        battery: BatteryStore = BatteryStore(),
        network: NetworkStore = NetworkStore(),
        projectPulse: ProjectPulseStore = ProjectPulseStore(),
        githubInbox: GitHubInboxStore = GitHubInboxStore(),
        docker: DockerStore = DockerStore(),
        customTile: CustomTileStore = CustomTileStore(),
        focusTimer: FocusTimerStore = FocusTimerStore()
    ) {
        self.usage = usage
        self.systemStats = systemStats
        self.serviceMonitor = serviceMonitor
        self.weather = weather
        self.schedule = schedule
        self.clock = clock
        self.music = music
        self.battery = battery
        self.network = network
        self.projectPulse = projectPulse
        self.githubInbox = githubInbox
        self.docker = docker
        self.customTile = customTile
        self.focusTimer = focusTimer
        var runtimes: [PanelModuleID: any PanelModuleRuntime] = [
            .usage: usage,
            .systemStats: systemStats,
            .serviceMonitor: serviceMonitor,
            .weather: weather,
            .schedule: schedule,
            .clock: clock,
            .music: music,
            .battery: battery,
            .network: network,
            .projectPulse: projectPulse,
            .githubInbox: githubInbox,
            .docker: docker,
            .customTile: customTile,
            .focusTimer: focusTimer,
        ]
        for module in PanelModuleID.extraCustomTiles {
            runtimes[module] = CustomTileStore(
                configuration: PanelSettings.customTileConfiguration(for: module))
        }
        self.runtimes = runtimes
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
    @ObservedObject var presentation: ReadOnlyDeckPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            moduleView
                .id(presentation.activeModule?.rawValue ?? "empty")
                .transition(moduleTransition)
            if let pageIndicator = presentation.pageIndicator {
                Text(pageIndicator)
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: presentation.theme.foregroundColor))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.28), in: Capsule())
                    .padding(4)
                    .transition(.opacity)
                    .accessibilityLabel("Module \(pageIndicator)")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: presentation.activeModule)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: presentation.pageIndicator)
    }

    private var moduleTransition: AnyTransition {
        guard let plan = DeckTransitionPlan.resolved(
            direction: presentation.direction, reduceMotion: reduceMotion)
        else { return .identity }
        return .asymmetric(
            insertion: .move(edge: plan.insertionEdge).combined(with: .opacity),
            removal: .move(edge: plan.removalEdge).combined(with: .opacity))
    }

    @ViewBuilder private var moduleView: some View {
        switch presentation.activeModule {
        case .usage:
            QuotaPanelView(
                store: services.usage, theme: presentation.theme, configuration: .current)
        case .systemStats:
            SystemStatsPanelView(store: services.systemStats, theme: presentation.theme)
        case .serviceMonitor:
            ServiceMonitorPanelView(store: services.serviceMonitor, theme: presentation.theme)
        case .weather:
            WeatherPanelView(store: services.weather, theme: presentation.theme)
        case .schedule:
            SchedulePanelView(store: services.schedule, theme: presentation.theme)
        case .clock:
            ClockPanelView(
                store: services.clock,
                theme: presentation.theme,
                timeZoneIdentifier: PanelSettings.clockTimeZoneIdentifier,
                hourFormat: PanelSettings.clockHourFormat)
        case .music:
            MusicPanelView(store: services.music, theme: presentation.theme)
        case .battery:
            BatteryPanelView(store: services.battery, theme: presentation.theme)
        case .network:
            NetworkPanelView(store: services.network, theme: presentation.theme)
        case .projectPulse:
            ProjectPulsePanelView(store: services.projectPulse, theme: presentation.theme)
        case .githubInbox:
            GitHubInboxPanelView(store: services.githubInbox, theme: presentation.theme)
        case .docker:
            DockerPanelView(store: services.docker, theme: presentation.theme)
        case .customTile, .customTile2, .customTile3:
            if let module = presentation.activeModule,
                let store = services.runtime(for: module) as? CustomTileStore
            {
                CustomTilePanelView(store: store, theme: presentation.theme)
            }
        case .focusTimer:
            FocusTimerPanelView(store: services.focusTimer, theme: presentation.theme)
        default:
            EmptyView()
        }
    }
}

struct ReadOnlyModuleDetailView: View {
    let services: PanelModuleServices
    @ObservedObject var presentation: ReadOnlyDeckPresentation
    var onOpenSettings: ((SettingsPaneID) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: definition?.symbolName ?? "rectangle.stack")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition?.title ?? "Module")
                        .font(.headline)
                    Text(definition?.subtitle ?? "DockDeck module detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onOpenSettings {
                    Menu {
                        Button("Module Settings…") { onOpenSettings(definition?.settingsPane ?? .decks) }
                        Button("Diagnostics…") { onOpenSettings(.diagnostics) }
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            Divider()

            detailContent
                .padding(16)
        }
        .frame(minWidth: 420, minHeight: 190)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var definition: PanelModuleDefinition? {
        presentation.activeModule.flatMap { PanelModuleRegistry.definition(for: $0) }
    }

    @ViewBuilder private var detailContent: some View {
        switch presentation.activeModule {
        case .network:
            NetworkModuleDetailView(store: services.network)
        case .battery:
            BatteryModuleDetailView(store: services.battery)
        case .usage:
            UsageModuleDetailView(store: services.usage, theme: presentation.theme)
        case .systemStats:
            SystemStatsModuleDetailView(
                store: services.systemStats, theme: presentation.theme)
        case .serviceMonitor:
            ServiceMonitorModuleDetailView(
                store: services.serviceMonitor, theme: presentation.theme)
        case .weather:
            WeatherModuleDetailView(store: services.weather)
        case .schedule:
            ScheduleModuleDetailView(store: services.schedule, theme: presentation.theme)
        case .clock:
            ClockModuleDetailView(store: services.clock, timeZoneIdentifier: PanelSettings.clockTimeZoneIdentifier,
                hourFormat: PanelSettings.clockHourFormat, favorites: PanelSettings.clockFavorites)
        case .music:
            MusicModuleDetailView(store: services.music, theme: presentation.theme)
        case .projectPulse:
            ProjectPulseModuleDetailView(
                store: services.projectPulse, theme: presentation.theme)
        case .githubInbox:
            GitHubInboxDetailView(store: services.githubInbox, theme: presentation.theme)
        case .docker:
            DockerModuleDetailView(store: services.docker, theme: presentation.theme)
        case .focusTimer:
            FocusTimerModuleDetailView(store: services.focusTimer)
        case .customTile, .customTile2, .customTile3:
            if let module = presentation.activeModule,
                let store = services.runtime(for: module) as? CustomTileStore
            {
                CustomTileModuleDetailView(store: store)
            }
        default:
            ReadOnlyDeckPanelView(services: services, presentation: presentation)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.12)))
        }
    }
}
