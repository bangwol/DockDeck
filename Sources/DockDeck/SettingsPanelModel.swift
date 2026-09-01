import Cocoa
import Combine

enum SettingsPaneID: String, CaseIterable, Identifiable {
    case decks
    case terminal
    case usage
    case systemStats
    case serviceMonitor
    case weather
    case schedule
    case clock
    case battery
    case network
    case appearance

    var id: Self { self }

    var title: String {
        switch self {
        case .decks: "Decks"
        case .terminal: "Terminal"
        case .usage: "Usage"
        case .systemStats: "System Stats"
        case .serviceMonitor: "Service Monitor"
        case .weather: "Weather"
        case .schedule: "Schedule"
        case .clock: "World Clock"
        case .battery: "Battery"
        case .network: "Network"
        case .appearance: "Appearance"
        }
    }

    var subtitle: String {
        switch self {
        case .decks: "Choose which modules appear beside the Dock."
        case .terminal: "Control terminal expansion and text."
        case .usage: "Choose how account limits are displayed."
        case .systemStats: "Monitor local CPU, memory, and disk usage."
        case .serviceMonitor: "Check the availability of your services."
        case .weather: "Show current conditions for a selected city."
        case .schedule: "Show the current or next calendar event."
        case .clock: "Show local time or another time zone."
        case .battery: "Show charge, power state, and time remaining."
        case .network: "Show local download and upload throughput."
        case .appearance: "Adjust the shared panel surface."
        }
    }

    var symbolName: String {
        switch self {
        case .decks: "rectangle.stack"
        case .terminal: "terminal"
        case .usage: "chart.bar"
        case .systemStats: "gauge.with.dots.needle.67percent"
        case .serviceMonitor: "network"
        case .weather: "cloud.sun"
        case .schedule: "calendar"
        case .clock: "clock"
        case .battery: "battery.75percent"
        case .network: "network"
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

enum PanelModuleRegistry {
    static let all = [
        PanelModuleDefinition(
            id: .terminal, title: "Terminal", subtitle: "Interactive login shell",
            symbolName: "terminal", settingsPane: .terminal),
        PanelModuleDefinition(
            id: .usage, title: "Usage", subtitle: "Codex and Claude limits",
            symbolName: "chart.bar", settingsPane: .usage),
        PanelModuleDefinition(
            id: .systemStats, title: "System Stats", subtitle: "CPU, memory, and disk",
            symbolName: "gauge.with.dots.needle.67percent", settingsPane: .systemStats),
        PanelModuleDefinition(
            id: .serviceMonitor, title: "Service Monitor", subtitle: "HTTPS availability",
            symbolName: "network", settingsPane: .serviceMonitor),
        PanelModuleDefinition(
            id: .weather, title: "Weather", subtitle: "Selected-city conditions",
            symbolName: "cloud.sun", settingsPane: .weather),
        PanelModuleDefinition(
            id: .schedule, title: "Schedule", subtitle: "Current and next event",
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
    var fontName: String
    var fontSize: CGFloat
    var displayMode: UsageDisplayMode
    var textColor: UsageTextColor
}

struct SystemStatsSettingsState: Equatable {
    var refreshInterval: TimeInterval
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
    var includeAllDay: Bool
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
    var terminal: TerminalSettingsState
    var usage: UsageSettingsState
    var systemStats: SystemStatsSettingsState
    var serviceMonitor: ServiceMonitorSettingsState
    var weather: WeatherSettingsState
    var schedule: ScheduleSettingsState
    var clock: ClockSettingsState
    var battery: BatterySettingsState
    var network: NetworkSettingsState
    var appearance: AppearanceSettingsState

    func normalized() -> Self {
        var values = self
        values.deckConfiguration = deckConfiguration.normalized()
        return values
    }
}

enum TerminalSettingsChange {
    case focusSize(width: CGFloat, height: CGFloat)
    case font(String)
}

enum UsageSettingsChange {
    case providers([UsageProviderID])
    case displayMode(UsageDisplayMode)
    case font(String)
    case fontSize(CGFloat)
    case textColor(UsageTextColor)
}

enum SystemStatsSettingsChange {
    case refreshInterval(TimeInterval)
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
    case includeAllDay(Bool)
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

enum AppearanceSettingsChange {
    case cornerRadius(CGFloat)
    case tintOpacity(CGFloat)
}

enum SettingsPanelChange {
    case deck(PanelDeckConfiguration)
    case terminal(TerminalSettingsChange)
    case usage(UsageSettingsChange)
    case systemStats(SystemStatsSettingsChange)
    case serviceMonitor(ServiceMonitorSettingsChange)
    case weather(WeatherSettingsChange)
    case schedule(ScheduleSettingsChange)
    case clock(ClockSettingsChange)
    case battery(BatterySettingsChange)
    case network(NetworkSettingsChange)
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
            || selectedPane == .decks || selectedPane == .appearance
            ? selectedPane : .decks
    }

    var moduleDefinitions: [PanelModuleDefinition] {
        Self.moduleDefinitions(in: values.deckConfiguration)
    }

    var availablePanes: [SettingsPaneID] {
        var panes: [SettingsPaneID] = [.decks]
        for pane in moduleDefinitions.compactMap(\.settingsPane) where !panes.contains(pane) {
            panes.append(pane)
        }
        if !panes.contains(.appearance) { panes.append(.appearance) }
        return panes
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

    func swapDecks() {
        var configuration = values.deckConfiguration
        swap(&configuration.left, &configuration.right)
        publishDeck(configuration)
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

    func setSystemStatsRefreshInterval(_ value: TimeInterval) {
        let selected = PanelSettings.systemStatsRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultSystemStatsRefreshInterval
        updateValues { $0.systemStats.refreshInterval = selected }
        onChange?(.systemStats(.refreshInterval(selected)))
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

    func setValues(_ values: SettingsPanelValues) {
        self.values = values.normalized()
        if !availablePanes.contains(selectedPane) { selectedPane = .decks }
    }

    private static func moduleDefinitions(
        in configuration: PanelDeckConfiguration
    ) -> [PanelModuleDefinition] {
        (configuration.left + configuration.right).compactMap {
            PanelModuleRegistry.definition(for: $0)
        }
    }

    private func updateValues(_ update: (inout SettingsPanelValues) -> Void) {
        var values = self.values
        update(&values)
        self.values = values
    }

    private func publishDeck(_ configuration: PanelDeckConfiguration) {
        let configuration = configuration.normalized()
        updateValues { $0.deckConfiguration = configuration }
        onChange?(.deck(configuration))
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

    private func resolvedScheduleCalendarIDs(availableIDs: [String]) -> Set<String> {
        let stored = Set(values.schedule.calendarIDs)
        return stored.isEmpty ? Set(availableIDs) : Set(availableIDs.filter(stored.contains))
    }
}
