import Cocoa
import Combine

enum SettingsPaneID: String, CaseIterable, Identifiable {
    case decks
    case notifications
    case diagnostics
    case terminal
    case usage
    case systemStats
    case serviceMonitor
    case weather
    case schedule
    case clock
    case battery
    case network
    case projectPulse
    case githubInbox
    case docker
    case customTile
    case focusTimer
    case appearance

    var id: Self { self }

    var title: String {
        switch self {
        case .decks: "Decks"
        case .notifications: "Notifications"
        case .diagnostics: "Diagnostics"
        case .terminal: "Terminal"
        case .usage: "Usage"
        case .systemStats: "System Stats"
        case .serviceMonitor: "Service Monitor"
        case .weather: "Weather"
        case .schedule: "Schedule"
        case .clock: "World Clock"
        case .battery: "Battery"
        case .network: "Network"
        case .projectPulse: "Project Pulse"
        case .githubInbox: "GitHub Inbox"
        case .docker: "Docker"
        case .customTile: "Custom Tile"
        case .focusTimer: "Focus Timer"
        case .appearance: "Appearance"
        }
    }

    var subtitle: String {
        switch self {
        case .decks: "Choose which modules appear beside the Dock."
        case .notifications: "Choose which local events can alert you."
        case .diagnostics: "Check local tools, permissions, sensors, and connectivity."
        case .terminal: "Control terminal expansion and text."
        case .usage: "Choose how account limits are displayed."
        case .systemStats: "Choose compact local performance metrics."
        case .serviceMonitor: "Check the availability of your services."
        case .weather: "Show current conditions for a selected city."
        case .schedule: "Show the current event or next calendar and reminder item."
        case .clock: "Show local time or another time zone."
        case .battery: "Show charge, power state, and time left."
        case .network: "Show local download and upload throughput."
        case .projectPulse: "Show local Git or remote GitHub repository activity."
        case .githubInbox: "Summarize account notifications, reviews, and Actions failures."
        case .docker: "Show local container health and resource use."
        case .customTile: "Show bounded output from a trusted executable or Shortcut."
        case .focusTimer: "Run persistent focus and break countdowns."
        case .appearance: "Adjust the shared panel surface."
        }
    }

    var symbolName: String {
        switch self {
        case .decks: "rectangle.stack"
        case .notifications: "bell.badge"
        case .diagnostics: "stethoscope"
        case .terminal: "terminal"
        case .usage: "chart.bar"
        case .systemStats: "gauge.with.dots.needle.67percent"
        case .serviceMonitor: "server.rack"
        case .weather: "cloud.sun"
        case .schedule: "calendar"
        case .clock: "clock"
        case .battery: "battery.75percent"
        case .network: "network"
        case .projectPulse: "point.3.connected.trianglepath.dotted"
        case .githubInbox: "bell.badge"
        case .docker: "shippingbox"
        case .customTile: "command"
        case .focusTimer: "timer"
        case .appearance: "paintbrush"
        }
    }

    var windowTitle: String { "DockDeck — \(title)" }
}

struct PanelModuleDefinition: Identifiable, Equatable {
    let id: PanelModuleID
    let title: String
    let subtitle: String
    let symbolName: String
    let settingsPane: SettingsPaneID?
}

enum SettingsSidebarSectionID: String {
    case general
    case modules
    case interface
}

struct SettingsSidebarSection: Identifiable, Equatable {
    let id: SettingsSidebarSectionID
    let title: String
    let panes: [SettingsPaneID]
}

enum PanelModuleRegistry {
    static let all = [
        PanelModuleDefinition(
            id: .terminal, title: "Terminal", subtitle: "Interactive login shell",
            symbolName: "terminal", settingsPane: .terminal),
        PanelModuleDefinition(
            id: .usage, title: "Usage", subtitle: "Codex and Claude limits",
            symbolName: "chart.bar", settingsPane: .usage),
        PanelModuleDefinition(
            id: .systemStats, title: "System Stats", subtitle: "Selectable local metrics",
            symbolName: "gauge.with.dots.needle.67percent", settingsPane: .systemStats),
        PanelModuleDefinition(
            id: .serviceMonitor, title: "Service Monitor", subtitle: "HTTPS availability",
            symbolName: "server.rack", settingsPane: .serviceMonitor),
        PanelModuleDefinition(
            id: .weather, title: "Weather", subtitle: "Selected-city conditions",
            symbolName: "cloud.sun", settingsPane: .weather),
        PanelModuleDefinition(
            id: .schedule, title: "Schedule", subtitle: "Calendar and reminders",
            symbolName: "calendar", settingsPane: .schedule),
        PanelModuleDefinition(
            id: .clock, title: "World Clock", subtitle: "Local or selected time zone",
            symbolName: "clock", settingsPane: .clock),
        PanelModuleDefinition(
            id: .battery, title: "Battery", subtitle: "Charge and power state",
            symbolName: "battery.75percent", settingsPane: .battery),
        PanelModuleDefinition(
            id: .network, title: "Network", subtitle: "Download and upload rates",
            symbolName: "network", settingsPane: .network),
        PanelModuleDefinition(
            id: .projectPulse, title: "Project Pulse", subtitle: "Git and GitHub activity",
            symbolName: "point.3.connected.trianglepath.dotted", settingsPane: .projectPulse),
        PanelModuleDefinition(
            id: .githubInbox, title: "GitHub Inbox", subtitle: "Notifications and reviews",
            symbolName: "bell.badge", settingsPane: .githubInbox),
        PanelModuleDefinition(
            id: .docker, title: "Docker", subtitle: "Containers and resources",
            symbolName: "shippingbox", settingsPane: .docker),
        PanelModuleDefinition(
            id: .customTile, title: "Custom Tile", subtitle: "Command or Shortcut output",
            symbolName: "command", settingsPane: .customTile),
        PanelModuleDefinition(
            id: .focusTimer, title: "Focus Timer", subtitle: "Focus and break countdowns",
            symbolName: "timer", settingsPane: .focusTimer),
    ]

    static func definition(for id: PanelModuleID) -> PanelModuleDefinition? {
        all.first { $0.id == id }
    }

    static func definition(for settingsPane: SettingsPaneID) -> PanelModuleDefinition? {
        all.first { $0.settingsPane == settingsPane }
    }
}

struct TerminalSettingsState: Equatable {
    var focusWidthMultiplier: CGFloat
    var focusHeightMultiplier: CGFloat
    var fontName: String
}

struct UsageSettingsState: Equatable {
    var enabledProviders: [UsageProviderID]
    var claudeRefreshMode: ClaudeUsageRefreshMode
    var fontName: String
    var fontSize: CGFloat
    var displayMode: UsageDisplayMode
    var textColor: UsageTextColor
    var showsPace: Bool
}

struct SystemStatsSettingsState: Equatable {
    var refreshInterval: TimeInterval
    var metrics: [SystemStatsMetric]
}

struct ServiceMonitorSettingsState: Equatable {
    var endpoints: [ServiceMonitorEndpoint]
    var refreshInterval: TimeInterval
}

struct WeatherSettingsState: Equatable {
    var location: WeatherLocation?
    var temperatureUnit: WeatherTemperatureUnit
    var refreshInterval: TimeInterval
}

struct ScheduleSettingsState: Equatable {
    var calendarIDs: [String]
    var reminderListIDs: [String]
    var includeAllDay: Bool
    var includeReminders: Bool
    var refreshInterval: TimeInterval
}

struct ClockSettingsState: Equatable {
    var timeZoneIdentifier: String
    var hourFormat: ClockHourFormat
}

struct BatterySettingsState: Equatable {
    var refreshInterval: TimeInterval
}

struct NetworkSettingsState: Equatable {
    var refreshInterval: TimeInterval
}

struct AppearanceSettingsState: Equatable {
    var cornerRadius: CGFloat
    var tintOpacity: CGFloat
}

struct SettingsPanelValues: Equatable {
    var deckConfiguration: PanelDeckConfiguration
    var notifications: DockNotificationSettings
    var terminal: TerminalSettingsState
    var usage: UsageSettingsState
    var systemStats: SystemStatsSettingsState
    var serviceMonitor: ServiceMonitorSettingsState
    var weather: WeatherSettingsState
    var schedule: ScheduleSettingsState
    var clock: ClockSettingsState
    var battery: BatterySettingsState
    var network: NetworkSettingsState
    var projectPulse: ProjectPulseConfiguration
    var githubInbox: GitHubInboxConfiguration
    var docker: DockerConfiguration
    var customTile: CustomTileConfiguration
    var focusTimer: FocusTimerSettings
    var appearance: AppearanceSettingsState

    func normalized() -> Self {
        var values = self
        values.deckConfiguration = deckConfiguration.normalized()
        values.systemStats.metrics = SystemStatsMetric.normalized(systemStats.metrics)
        values.projectPulse = projectPulse.normalized()
        values.githubInbox = githubInbox.normalized()
        values.docker = docker.normalized()
        values.customTile = customTile.normalized()
        values.focusTimer = focusTimer.normalized()
        return values
    }
}

enum TerminalSettingsChange {
    case focusSize(width: CGFloat, height: CGFloat)
    case font(String)
}

enum UsageSettingsChange {
    case providers([UsageProviderID])
    case claudeRefreshMode(ClaudeUsageRefreshMode)
    case displayMode(UsageDisplayMode)
    case font(String)
    case fontSize(CGFloat)
    case textColor(UsageTextColor)
    case showsPace(Bool)
}

enum SystemStatsSettingsChange {
    case refreshInterval(TimeInterval)
    case metrics([SystemStatsMetric])
}

enum ServiceMonitorSettingsChange {
    case endpoints([ServiceMonitorEndpoint])
    case refreshInterval(TimeInterval)
}

enum WeatherSettingsChange {
    case location(WeatherLocation?)
    case temperatureUnit(WeatherTemperatureUnit)
    case refreshInterval(TimeInterval)
}

enum ScheduleSettingsChange {
    case calendarIDs([String])
    case reminderListIDs([String])
    case includeAllDay(Bool)
    case includeReminders(Bool)
    case refreshInterval(TimeInterval)
}

enum ClockSettingsChange {
    case timeZoneIdentifier(String)
    case hourFormat(ClockHourFormat)
}

enum BatterySettingsChange {
    case refreshInterval(TimeInterval)
}

enum NetworkSettingsChange {
    case refreshInterval(TimeInterval)
}

enum ProjectPulseSettingsChange {
    case configuration(ProjectPulseConfiguration)
}

enum GitHubInboxSettingsChange {
    case configuration(GitHubInboxConfiguration)
}

enum DockerSettingsChange {
    case configuration(DockerConfiguration)
}

enum FocusTimerSettingsChange {
    case settings(FocusTimerSettings)
}

enum AppearanceSettingsChange {
    case cornerRadius(CGFloat)
    case tintOpacity(CGFloat)
}

enum SettingsPanelChange {
    case deck(PanelDeckConfiguration)
    case notifications(DockNotificationSettings)
    case terminal(TerminalSettingsChange)
    case usage(UsageSettingsChange)
    case systemStats(SystemStatsSettingsChange)
    case serviceMonitor(ServiceMonitorSettingsChange)
    case weather(WeatherSettingsChange)
    case schedule(ScheduleSettingsChange)
    case clock(ClockSettingsChange)
    case battery(BatterySettingsChange)
    case network(NetworkSettingsChange)
    case projectPulse(ProjectPulseSettingsChange)
    case githubInbox(GitHubInboxSettingsChange)
    case docker(DockerSettingsChange)
    case customTile(CustomTileConfiguration)
    case focusTimer(FocusTimerSettingsChange)
    case appearance(AppearanceSettingsChange)
}

final class SettingsPanelModel: ObservableObject {
    @Published var selectedPane: SettingsPaneID {
        didSet { onPaneChange?(selectedPane) }
    }
    @Published private(set) var values: SettingsPanelValues

    let fontNames: [String]

    var onPaneChange: ((SettingsPaneID) -> Void)?
    var onChange: ((SettingsPanelChange) -> Void)?
    var onReset: (() -> Void)?
    var onCancel: (() -> Void)?

    init(
        selectedPane: SettingsPaneID,
        values: SettingsPanelValues,
        fontNames: [String]
    ) {
        let values = values.normalized()
        self.values = values

        var availableFonts = fontNames
        for selectedFont in [values.terminal.fontName, values.usage.fontName]
            where !availableFonts.contains(selectedFont)
        {
            availableFonts.insert(selectedFont, at: 0)
        }
        self.fontNames = availableFonts

        let modulePanes = Self.moduleDefinitions(in: values.deckConfiguration)
            .compactMap(\.settingsPane)
        self.selectedPane = modulePanes.contains(selectedPane)
            || selectedPane == .decks || selectedPane == .notifications
            || selectedPane == .diagnostics
            || selectedPane == .appearance
            ? selectedPane : .decks
    }

    var moduleDefinitions: [PanelModuleDefinition] {
        Self.moduleDefinitions(in: values.deckConfiguration)
    }

    var availablePanes: [SettingsPaneID] {
        sidebarSections.flatMap(\.panes)
    }

    var sidebarSections: [SettingsSidebarSection] {
        let modulePanes = moduleDefinitions.compactMap(\.settingsPane)
        return [
            SettingsSidebarSection(
                id: .general, title: "General", panes: [.decks, .notifications, .diagnostics]),
            SettingsSidebarSection(
                id: .modules, title: "Modules", panes: modulePanes),
            SettingsSidebarSection(
                id: .interface, title: "Interface", panes: [.appearance]),
        ]
    }

    func moduleDefinitions(on side: PanelSide) -> [PanelModuleDefinition] {
        let modules = side == .left
            ? values.deckConfiguration.left : values.deckConfiguration.right
        return modules.compactMap { PanelModuleRegistry.definition(for: $0) }
    }

    func side(containing module: PanelModuleID) -> PanelSide? {
        values.deckConfiguration.side(containing: module)
    }

    func isEnabled(_ module: PanelModuleID) -> Bool {
        values.deckConfiguration.contains(module)
    }

    func moduleDefinition(for pane: SettingsPaneID) -> PanelModuleDefinition? {
        PanelModuleRegistry.definition(for: pane)
    }

    func canDisable(_ module: PanelModuleID) -> Bool {
        !isEnabled(module)
            || moduleDefinitions.contains { $0.id != module && isEnabled($0.id) }
    }

    func selectPane(_ pane: SettingsPaneID) {
        guard availablePanes.contains(pane) else { return }
        selectedPane = pane
    }

    func setEnabled(_ enabled: Bool, for module: PanelModuleID) {
        guard enabled || canDisable(module) else { return }
        var configuration = values.deckConfiguration
        configuration.setEnabled(enabled, for: module)
        publishDeck(configuration)
    }

    func moveModule(
        _ module: PanelModuleID, to side: PanelSide, before target: PanelModuleID? = nil
    ) {
        guard module != target, PanelModuleRegistry.definition(for: module) != nil else { return }
        var configuration = values.deckConfiguration
        let destination = configuration.modules(on: side).filter { $0 != module }
        let index = target.flatMap(destination.firstIndex(of:)) ?? destination.count
        configuration.move(module, to: side, at: index)
        publishDeck(configuration)
    }

    func moveModuleUp(_ module: PanelModuleID) {
        guard let side = side(containing: module) else { return }
        let modules = values.deckConfiguration.modules(on: side)
        guard let index = modules.firstIndex(of: module), index > 0,
            isEnabled(modules[index - 1]) == isEnabled(module)
        else { return }
        var configuration = values.deckConfiguration
        configuration.move(module, to: side, at: index - 1)
        publishDeck(configuration)
    }

    func moveModuleDown(_ module: PanelModuleID) {
        guard let side = side(containing: module) else { return }
        let modules = values.deckConfiguration.modules(on: side)
        guard let index = modules.firstIndex(of: module), index + 1 < modules.count,
            isEnabled(modules[index + 1]) == isEnabled(module)
        else { return }
        var configuration = values.deckConfiguration
        configuration.move(module, to: side, at: index + 1)
        publishDeck(configuration)
    }

    func canMoveModuleUp(_ module: PanelModuleID) -> Bool {
        guard let side = side(containing: module) else { return false }
        let modules = values.deckConfiguration.modules(on: side)
        guard let index = modules.firstIndex(of: module), index > 0 else { return false }
        return isEnabled(modules[index - 1]) == isEnabled(module)
    }

    func canMoveModuleDown(_ module: PanelModuleID) -> Bool {
        guard let side = side(containing: module) else { return false }
        let modules = values.deckConfiguration.modules(on: side)
        guard let index = modules.firstIndex(of: module), index + 1 < modules.count else {
            return false
        }
        return isEnabled(modules[index + 1]) == isEnabled(module)
    }

    func swapDecks() {
        var configuration = values.deckConfiguration
        swap(&configuration.left, &configuration.right)
        publishDeck(configuration)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        updateNotifications { $0.enabled = enabled }
    }

    func setUsageAlertsEnabled(_ enabled: Bool) {
        updateNotifications { $0.usageAlerts = enabled }
    }

    func setUsageAlertThreshold(_ threshold: Int) {
        updateNotifications { $0.usageRemainingThreshold = threshold }
    }

    func setServiceFailureAlertsEnabled(_ enabled: Bool) {
        updateNotifications { $0.serviceFailureAlerts = enabled }
    }

    func setServiceRecoveryAlertsEnabled(_ enabled: Bool) {
        updateNotifications { $0.serviceRecoveryAlerts = enabled }
    }

    func setBatteryAlertsEnabled(_ enabled: Bool) {
        updateNotifications { $0.batteryAlerts = enabled }
    }

    func setBatteryAlertThreshold(_ threshold: Int) {
        updateNotifications { $0.batteryRemainingThreshold = threshold }
    }

    func setFocusTimerAlertsEnabled(_ enabled: Bool) {
        updateNotifications { $0.focusTimerAlerts = enabled }
    }

    func setCornerRadius(_ value: CGFloat) {
        let value = value.rounded()
        updateValues { $0.appearance.cornerRadius = value }
        onChange?(.appearance(.cornerRadius(value)))
    }

    func setTintOpacity(_ value: CGFloat) {
        let value = (value * 100).rounded() / 100
        updateValues { $0.appearance.tintOpacity = value }
        onChange?(.appearance(.tintOpacity(value)))
    }

    func setFocusWidthMultiplier(_ value: CGFloat) {
        let value = (value * 4).rounded() / 4
        updateValues { $0.terminal.focusWidthMultiplier = value }
        publishFocusSize()
    }

    func setFocusHeightMultiplier(_ value: CGFloat) {
        let value = (value * 4).rounded() / 4
        updateValues { $0.terminal.focusHeightMultiplier = value }
        publishFocusSize()
    }

    func setTerminalFontName(_ value: String) {
        updateValues { $0.terminal.fontName = value }
        onChange?(.terminal(.font(value)))
    }

    func setUsageFontName(_ value: String) {
        updateValues { $0.usage.fontName = value }
        onChange?(.usage(.font(value)))
    }

    func isUsageProviderEnabled(_ provider: UsageProviderID) -> Bool {
        values.usage.enabledProviders.contains(provider)
    }

    func canDisableUsageProvider(_ provider: UsageProviderID) -> Bool {
        !isUsageProviderEnabled(provider) || values.usage.enabledProviders.count > 1
    }

    func setUsageProvider(_ provider: UsageProviderID, enabled: Bool) {
        guard enabled || canDisableUsageProvider(provider) else { return }
        var providers = values.usage.enabledProviders.filter { $0 != provider }
        if enabled { providers.append(provider) }
        providers = UsageProviderID.allCases.filter(Set(providers).contains)
        updateValues { $0.usage.enabledProviders = providers }
        onChange?(.usage(.providers(providers)))
    }

    func setClaudeUsageRefreshMode(_ value: ClaudeUsageRefreshMode) {
        updateValues { $0.usage.claudeRefreshMode = value }
        onChange?(.usage(.claudeRefreshMode(value)))
    }

    func setUsageFontSize(_ value: CGFloat) {
        let value = value.rounded()
        updateValues { $0.usage.fontSize = value }
        onChange?(.usage(.fontSize(value)))
    }

    func setUsageDisplayMode(_ value: UsageDisplayMode) {
        updateValues { $0.usage.displayMode = value }
        onChange?(.usage(.displayMode(value)))
    }

    func setUsageTextColor(_ value: UsageTextColor) {
        updateValues { $0.usage.textColor = value }
        onChange?(.usage(.textColor(value)))
    }

    func setUsageShowsPace(_ value: Bool) {
        updateValues { $0.usage.showsPace = value }
        onChange?(.usage(.showsPace(value)))
    }

    func setSystemStatsRefreshInterval(_ value: TimeInterval) {
        let selected = PanelSettings.systemStatsRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultSystemStatsRefreshInterval
        updateValues { $0.systemStats.refreshInterval = selected }
        onChange?(.systemStats(.refreshInterval(selected)))
    }

    func isSystemStatsMetricEnabled(_ metric: SystemStatsMetric) -> Bool {
        values.systemStats.metrics.contains(metric)
    }

    func canSetSystemStatsMetric(_ metric: SystemStatsMetric, enabled: Bool) -> Bool {
        let count = values.systemStats.metrics.count
        if enabled { return !isSystemStatsMetricEnabled(metric) && count < SystemStatsMetric.maximumSelectionCount }
        return isSystemStatsMetricEnabled(metric) && count > SystemStatsMetric.minimumSelectionCount
    }

    func setSystemStatsMetric(_ metric: SystemStatsMetric, enabled: Bool) {
        guard canSetSystemStatsMetric(metric, enabled: enabled) else { return }
        var metrics = values.systemStats.metrics.filter { $0 != metric }
        if enabled { metrics.append(metric) }
        metrics = SystemStatsMetric.normalized(metrics)
        updateValues { $0.systemStats.metrics = metrics }
        onChange?(.systemStats(.metrics(metrics)))
    }

    func addServiceMonitorEndpoint() {
        guard values.serviceMonitor.endpoints.count < ServiceMonitorEndpoint.maximumCount else {
            return
        }
        var endpoints = values.serviceMonitor.endpoints
        endpoints.append(
            ServiceMonitorEndpoint(
                name: "Service \(endpoints.count + 1)", urlString: "https://"))
        publishServiceMonitorEndpoints(endpoints)
    }

    func removeServiceMonitorEndpoint(_ id: UUID) {
        publishServiceMonitorEndpoints(
            values.serviceMonitor.endpoints.filter { $0.id != id })
    }

    func setServiceMonitorEndpointName(_ id: UUID, name: String) {
        updateServiceMonitorEndpoint(id) { $0.name = name }
    }

    func setServiceMonitorEndpointURL(_ id: UUID, urlString: String) {
        updateServiceMonitorEndpoint(id) { $0.urlString = urlString }
    }

    func setServiceMonitorRefreshInterval(_ value: TimeInterval) {
        let selected = PanelSettings.serviceMonitorRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultServiceMonitorRefreshInterval
        updateValues { $0.serviceMonitor.refreshInterval = selected }
        onChange?(.serviceMonitor(.refreshInterval(selected)))
    }

    func setWeatherLocation(_ location: WeatherLocation?) {
        let location = location?.normalizedForStorage()
        updateValues { $0.weather.location = location }
        onChange?(.weather(.location(location)))
    }

    func setWeatherTemperatureUnit(_ unit: WeatherTemperatureUnit) {
        updateValues { $0.weather.temperatureUnit = unit }
        onChange?(.weather(.temperatureUnit(unit)))
    }

    func setWeatherRefreshInterval(_ value: TimeInterval) {
        let selected = PanelSettings.weatherRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultWeatherRefreshInterval
        updateValues { $0.weather.refreshInterval = selected }
        onChange?(.weather(.refreshInterval(selected)))
    }

    func isScheduleCalendarEnabled(_ id: String, availableIDs: [String]) -> Bool {
        resolvedScheduleCalendarIDs(availableIDs: availableIDs).contains(id)
    }

    func canDisableScheduleCalendar(_ id: String, availableIDs: [String]) -> Bool {
        let selected = resolvedScheduleCalendarIDs(availableIDs: availableIDs)
        return !selected.contains(id) || selected.count > 1
    }

    func setScheduleCalendar(_ id: String, enabled: Bool, availableIDs: [String]) {
        var selected = resolvedScheduleCalendarIDs(availableIDs: availableIDs)
        if enabled {
            selected.insert(id)
        } else {
            guard selected.count > 1 else { return }
            selected.remove(id)
        }
        let identifiers = availableIDs.filter(selected.contains)
        updateValues { $0.schedule.calendarIDs = identifiers }
        onChange?(.schedule(.calendarIDs(identifiers)))
    }

    func setScheduleIncludesAllDay(_ value: Bool) {
        updateValues { $0.schedule.includeAllDay = value }
        onChange?(.schedule(.includeAllDay(value)))
    }

    func isScheduleReminderListEnabled(_ id: String, availableIDs: [String]) -> Bool {
        resolvedScheduleReminderListIDs(availableIDs: availableIDs).contains(id)
    }

    func canDisableScheduleReminderList(_ id: String, availableIDs: [String]) -> Bool {
        let selected = resolvedScheduleReminderListIDs(availableIDs: availableIDs)
        return !selected.contains(id) || selected.count > 1
    }

    func setScheduleReminderList(_ id: String, enabled: Bool, availableIDs: [String]) {
        var selected = resolvedScheduleReminderListIDs(availableIDs: availableIDs)
        if enabled {
            selected.insert(id)
        } else {
            guard selected.count > 1 else { return }
            selected.remove(id)
        }
        let identifiers = availableIDs.filter(selected.contains)
        updateValues { $0.schedule.reminderListIDs = identifiers }
        onChange?(.schedule(.reminderListIDs(identifiers)))
    }

    func setScheduleIncludesReminders(_ value: Bool) {
        updateValues { $0.schedule.includeReminders = value }
        onChange?(.schedule(.includeReminders(value)))
    }

    func setScheduleRefreshInterval(_ value: TimeInterval) {
        let selected = PanelSettings.scheduleRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultScheduleRefreshInterval
        updateValues { $0.schedule.refreshInterval = selected }
        onChange?(.schedule(.refreshInterval(selected)))
    }

    func setClockTimeZoneIdentifier(_ value: String) {
        let identifier = ClockTimeZone.normalized(identifier: value)
        updateValues { $0.clock.timeZoneIdentifier = identifier }
        onChange?(.clock(.timeZoneIdentifier(identifier)))
    }

    func setClockHourFormat(_ value: ClockHourFormat) {
        updateValues { $0.clock.hourFormat = value }
        onChange?(.clock(.hourFormat(value)))
    }

    func setBatteryRefreshInterval(_ value: TimeInterval) {
        let selected = PanelSettings.batteryRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultBatteryRefreshInterval
        updateValues { $0.battery.refreshInterval = selected }
        onChange?(.battery(.refreshInterval(selected)))
    }

    func setNetworkRefreshInterval(_ value: TimeInterval) {
        let selected = PanelSettings.networkRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultNetworkRefreshInterval
        updateValues { $0.network.refreshInterval = selected }
        onChange?(.network(.refreshInterval(selected)))
    }

    func setProjectPulseRepositoryPath(_ path: String?) {
        updateProjectPulseConfiguration { $0.repositoryPath = path }
    }

    func setProjectPulseSource(_ source: ProjectPulseSource) {
        updateProjectPulseConfiguration { $0.source = source }
    }

    func setProjectPulseGitHubScope(_ scope: GitHubPulseScope) {
        updateProjectPulseConfiguration { $0.githubScope = scope }
    }

    func setProjectPulseGitHubRepository(_ repository: String?) {
        updateProjectPulseConfiguration { $0.githubRepository = repository }
    }

    func setProjectPulseIncludesGitHubActions(_ value: Bool) {
        updateProjectPulseConfiguration { $0.includesGitHubActions = value }
    }

    func setProjectPulseRefreshInterval(_ value: TimeInterval) {
        updateProjectPulseConfiguration { $0.refreshInterval = value }
    }

    func setGitHubInboxActionsRepository(_ repository: String?) {
        updateGitHubInboxConfiguration { $0.actionsRepository = repository }
    }

    func setGitHubInboxRefreshInterval(_ value: TimeInterval) {
        updateGitHubInboxConfiguration { $0.refreshInterval = value }
    }

    func setDockerRefreshInterval(_ value: TimeInterval) {
        var configuration = values.docker
        configuration.refreshInterval = value
        configuration = configuration.normalized()
        updateValues { $0.docker = configuration }
        onChange?(.docker(.configuration(configuration)))
    }

    func setCustomTileTitle(_ value: String) {
        updateCustomTileConfiguration { $0.title = value }
    }

    func setCustomTileSource(_ value: CustomTileSource) {
        updateCustomTileConfiguration { $0.source = value }
    }

    func setCustomTileExecutablePath(_ value: String) {
        updateCustomTileConfiguration { $0.executablePath = value }
    }

    func setCustomTileArguments(_ value: String) {
        let arguments = value.split(whereSeparator: { $0.isNewline }).map(String.init)
        updateCustomTileConfiguration { $0.arguments = arguments }
    }

    func setCustomTileShortcutName(_ value: String) {
        updateCustomTileConfiguration { $0.shortcutName = value }
    }

    func setCustomTileRefreshInterval(_ value: TimeInterval) {
        updateCustomTileConfiguration { $0.refreshInterval = value }
    }

    func setFocusTimerFocusMinutes(_ value: Int) {
        updateFocusTimerSettings { $0.focusMinutes = value }
    }

    func setFocusTimerBreakMinutes(_ value: Int) {
        updateFocusTimerSettings { $0.breakMinutes = value }
    }

    func setValues(_ values: SettingsPanelValues) {
        self.values = values.normalized()
        if !availablePanes.contains(selectedPane) { selectedPane = .decks }
    }

    private static func moduleDefinitions(
        in configuration: PanelDeckConfiguration
    ) -> [PanelModuleDefinition] {
        let definitions = (configuration.left + configuration.right).compactMap {
            PanelModuleRegistry.definition(for: $0)
        }
        let enabled = Set(configuration.enabled)
        return definitions.sorted { lhs, rhs in
            let lhsEnabled = enabled.contains(lhs.id)
            let rhsEnabled = enabled.contains(rhs.id)
            if lhsEnabled != rhsEnabled { return lhsEnabled }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func updateValues(_ update: (inout SettingsPanelValues) -> Void) {
        var values = self.values
        update(&values)
        self.values = values
    }

    private func publishDeck(_ configuration: PanelDeckConfiguration) {
        let configuration = configuration.normalized()
        guard configuration != values.deckConfiguration else { return }
        updateValues { $0.deckConfiguration = configuration }
        onChange?(.deck(configuration))
    }

    private func updateNotifications(
        _ update: (inout DockNotificationSettings) -> Void
    ) {
        var settings = values.notifications
        update(&settings)
        settings = settings.normalized()
        updateValues { $0.notifications = settings }
        onChange?(.notifications(settings))
    }

    private func publishFocusSize() {
        onChange?(
            .terminal(
                .focusSize(
                    width: values.terminal.focusWidthMultiplier,
                    height: values.terminal.focusHeightMultiplier)))
    }

    private func updateServiceMonitorEndpoint(
        _ id: UUID, update: (inout ServiceMonitorEndpoint) -> Void
    ) {
        var endpoints = values.serviceMonitor.endpoints
        guard let index = endpoints.firstIndex(where: { $0.id == id }) else { return }
        update(&endpoints[index])
        publishServiceMonitorEndpoints(endpoints)
    }

    private func publishServiceMonitorEndpoints(_ endpoints: [ServiceMonitorEndpoint]) {
        let endpoints = Array(endpoints.prefix(ServiceMonitorEndpoint.maximumCount))
        updateValues { $0.serviceMonitor.endpoints = endpoints }
        onChange?(.serviceMonitor(.endpoints(endpoints)))
    }

    private func updateProjectPulseConfiguration(
        _ update: (inout ProjectPulseConfiguration) -> Void
    ) {
        var configuration = values.projectPulse
        update(&configuration)
        configuration = configuration.normalized()
        updateValues { $0.projectPulse = configuration }
        onChange?(.projectPulse(.configuration(configuration)))
    }

    private func updateGitHubInboxConfiguration(
        _ update: (inout GitHubInboxConfiguration) -> Void
    ) {
        var configuration = values.githubInbox
        update(&configuration)
        configuration = configuration.normalized()
        updateValues { $0.githubInbox = configuration }
        onChange?(.githubInbox(.configuration(configuration)))
    }

    private func updateCustomTileConfiguration(
        _ update: (inout CustomTileConfiguration) -> Void
    ) {
        var configuration = values.customTile
        update(&configuration)
        configuration = configuration.normalized()
        updateValues { $0.customTile = configuration }
        onChange?(.customTile(configuration))
    }

    private func updateFocusTimerSettings(
        _ update: (inout FocusTimerSettings) -> Void
    ) {
        var settings = values.focusTimer
        update(&settings)
        settings = settings.normalized()
        updateValues { $0.focusTimer = settings }
        onChange?(.focusTimer(.settings(settings)))
    }

    private func resolvedScheduleCalendarIDs(availableIDs: [String]) -> Set<String> {
        let stored = Set(values.schedule.calendarIDs)
        return stored.isEmpty ? Set(availableIDs) : Set(availableIDs.filter(stored.contains))
    }

    private func resolvedScheduleReminderListIDs(availableIDs: [String]) -> Set<String> {
        let stored = Set(values.schedule.reminderListIDs)
        return stored.isEmpty ? Set(availableIDs) : Set(availableIDs.filter(stored.contains))
    }
}
