import Cocoa
import Combine

final class SettingsPanelModel: ObservableObject {
    @Published var selectedPane: SettingsPaneID {
        didSet { onPaneChange?(selectedPane) }
    }
    @Published private(set) var values: SettingsPanelValues
    @Published private(set) var recentlyActivatedModule: PanelModuleID?

    let fontNames: [String]

    var onPaneChange: ((SettingsPaneID) -> Void)?
    var onChange: ((SettingsPanelChange) -> Void)?
    var onReset: (() -> Void)?
    var onCancel: (() -> Void)?
    private var activationHighlightGeneration = UUID()

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

    func enabledModuleDefinitions(on side: PanelSide) -> [PanelModuleDefinition] {
        moduleDefinitions(on: side).filter { isEnabled($0.id) }
    }

    var inactiveModuleDefinitions: [PanelModuleDefinition] {
        moduleDefinitions.filter { !isEnabled($0.id) }
    }

    func side(containing module: PanelModuleID) -> PanelSide? {
        values.deckConfiguration.side(containing: module)
    }

    func isEnabled(_ module: PanelModuleID) -> Bool {
        values.deckConfiguration.contains(module)
    }

    func isAutoSliding(_ module: PanelModuleID) -> Bool {
        values.deckAutoSlide.contains(module)
    }

    func autoSlideModules(on side: PanelSide) -> [PanelModuleID] {
        values.deckAutoSlide.modules(on: side, configuration: values.deckConfiguration)
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
        guard enabled != isEnabled(module) else { return }
        guard enabled || canDisable(module) else { return }
        if enabled {
            activateModule(module, on: preferredActivationSide())
            return
        }
        if isAutoSliding(module) {
            var settings = values.deckAutoSlide
            settings.setEnabled(false, for: module)
            publishDeckAutoSlide(settings)
        }
        var configuration = values.deckConfiguration
        configuration.setEnabled(false, for: module)
        publishDeck(configuration)
    }

    func activateModule(
        _ module: PanelModuleID, on side: PanelSide, before target: PanelModuleID? = nil
    ) {
        guard PanelModuleRegistry.definition(for: module) != nil else { return }
        guard !isEnabled(module) else {
            moveModule(module, to: side, before: target)
            return
        }
        var configuration = values.deckConfiguration
        configuration.setEnabled(true, for: module)
        let destination = configuration.modules(on: side).filter { $0 != module }
        let index = target.flatMap(destination.firstIndex(of:)) ?? destination.count
        configuration.move(module, to: side, at: index)
        publishDeck(configuration)
        emphasizeActivatedModule(module)
    }

    func setAutoSlideEnabled(_ enabled: Bool, for module: PanelModuleID) {
        guard isEnabled(module) else { return }
        var settings = values.deckAutoSlide
        settings.setEnabled(enabled, for: module)
        publishDeckAutoSlide(settings)
    }

    func setAutoSlideInterval(_ interval: TimeInterval) {
        var settings = values.deckAutoSlide
        settings.interval = interval
        publishDeckAutoSlide(settings)
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

    private func preferredActivationSide() -> PanelSide {
        let configuration = values.deckConfiguration
        let leftCount = configuration.enabledModules(on: .left).count
        let rightCount = configuration.enabledModules(on: .right).count
        return leftCount <= rightCount ? .left : .right
    }

    private func emphasizeActivatedModule(_ module: PanelModuleID) {
        let generation = UUID()
        activationHighlightGeneration = generation
        recentlyActivatedModule = module
        let phases: [(TimeInterval, PanelModuleID?)] = [
            (0.22, nil), (0.42, module), (0.72, nil),
        ]
        for (delay, value) in phases {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.activationHighlightGeneration == generation else { return }
                self.recentlyActivatedModule = value
            }
        }
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

    func setSystemThermalAlertsEnabled(_ enabled: Bool) {
        updateNotifications { $0.systemThermalAlerts = enabled }
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

    private func publishDeckAutoSlide(_ settings: DeckAutoSlideSettings) {
        let settings = settings.normalized()
        guard settings != values.deckAutoSlide else { return }
        updateValues { $0.deckAutoSlide = settings }
        onChange?(.deckAutoSlide(settings))
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
