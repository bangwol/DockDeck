import Cocoa

extension AppDelegate {
    @objc func toggleSettingsPanel(_ sender: Any?) {
        if let settingsPanel {
            focusSettingsPanel(settingsPanel)
            return
        }

        let terminalVisible = panel.isVisible
        let anchor = terminalVisible
            ? panel
            : readOnlyDeckPanelControllers.first(where: { $0.panel.isVisible })?.panel ?? panel
        presentSettingsPanel(
            pane: savedSettingsPane,
            anchor: anchor,
            restoreTerminalFocus: terminalVisible)
    }

    @objc func openReadOnlyModuleSettings(_ sender: Any?) {
        let controller = readOnlyDeckController(from: sender)
            ?? readOnlyDeckPanelControllers.first(where: { $0.panel.isVisible })
            ?? rightReadOnlyDeckPanelController
        let pane = controller?.activeModule
            .flatMap { PanelModuleRegistry.definition(for: $0)?.settingsPane } ?? .decks
        if let settingsPanel {
            (settingsPanel.contentView as? SettingsPanelView)?.selectPane(pane)
            focusSettingsPanel(settingsPanel)
            return
        }
        presentSettingsPanel(pane: pane, anchor: controller?.panel ?? panel, restoreTerminalFocus: false)
    }

    @objc func showNextTerminalDeckModule(_ sender: Any?) {
        guard let side = PanelSettings.deckConfiguration.side(containing: .terminal),
            let next = ReadOnlyDeckSelection.next(
                after: .terminal, enabledModules: PanelSettings.enabledModules(on: side))
        else { return }
        PanelSettings.setActiveModule(next, on: side)
        deckSelectionDidChange(on: side)
    }

    @objc func selectTerminalDeckModule(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
            let rawValue = item.representedObject as? String,
            let side = PanelSettings.deckConfiguration.side(containing: .terminal)
        else { return }
        let module = PanelModuleID(rawValue: rawValue)
        guard PanelSettings.enabledModules(on: side).contains(module) else { return }
        PanelSettings.setActiveModule(module, on: side)
        deckSelectionDidChange(on: side)
    }

    func handleTerminalScrollWheel(_ event: NSEvent) -> Bool {
        guard TerminalScrollRoute.resolved(for: terminalPanelMode) == .deck,
            let side = PanelSettings.deckConfiguration.side(containing: .terminal)
        else { return false }
        let enabledModules = PanelSettings.enabledModules(on: side)
        guard enabledModules.count > 1,
            let direction = DeckScrollDirection.resolved(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY)
        else { return false }

        if !event.momentumPhase.isEmpty { return true }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTerminalDeckScrollSelectionTime >= 0.35 else { return true }
        lastTerminalDeckScrollSelectionTime = now

        let module: PanelModuleID?
        switch direction {
        case .previous:
            module = ReadOnlyDeckSelection.previous(
                before: .terminal, enabledModules: enabledModules)
        case .next:
            module = ReadOnlyDeckSelection.next(
                after: .terminal, enabledModules: enabledModules)
        }
        guard let module else { return false }
        PanelSettings.setActiveModule(module, on: side)
        deckSelectionDidChange(on: side)
        return true
    }

    @objc func toggleUsageDisplayMode(_ sender: Any?) {
        PanelSettings.usageDisplayMode =
            PanelSettings.usageDisplayMode == .remaining ? .used : .remaining
        for controller in readOnlyDeckPanelControllers { controller.applySettings() }
    }

    @objc func swapPanelSides(_ sender: Any?) {
        PanelSettings.panelOrder =
            PanelSettings.panelOrder == .terminalLeft ? .terminalRight : .terminalLeft
        applyPanelOrder()
    }

    func deckSelectionDidChange(on side: PanelSide) {
        debugLog("deck-selection", side.rawValue)
        if terminalPanelMode != .docked {
            terminalPanelMode = .docked
            expansionScreenID = nil
            terminalPanelController.setResizable(false)
            applyTerminalAppearance()
        }
        for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        synchronizeModuleRuntimes()
        isFrozen = false
        refreshCoarseCaches()
        runEvaluation()
    }

    /// The accessory app may be inactive while its floating panel stays visible, in which
    /// case ordering front alone leaves keyboard focus in the previous application.
    private func focusSettingsPanel(_ settingsPanel: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel.makeKeyAndOrderFront(nil)
    }

    private func readOnlyDeckController(from sender: Any?) -> ReadOnlyDeckPanelController? {
        guard let rawValue = (sender as? NSMenuItem)?.representedObject as? String,
            let side = PanelSide(rawValue: rawValue)
        else { return nil }
        return readOnlyDeckPanelController(on: side)
    }

    private var savedSettingsPane: SettingsPaneID {
        UserDefaults.standard.string(forKey: AppPreferences.settingsPaneKey)
            .flatMap(SettingsPaneID.init(rawValue:)) ?? .decks
    }

    private func presentSettingsPanel(
        pane: SettingsPaneID, anchor: NSWindow, restoreTerminalFocus: Bool
    ) {
        UserDefaults.standard.set(pane.rawValue, forKey: AppPreferences.settingsPaneKey)
        let view = SettingsPanelView(
            selectedPane: pane,
            values: currentSettingsValues,
            fontNames: TerminalTheme.installedFontNames,
            scheduleStore: scheduleStore)

        view.onPaneChange = { [weak self] pane in
            UserDefaults.standard.set(pane.rawValue, forKey: AppPreferences.settingsPaneKey)
            self?.settingsPanel?.title = pane.windowTitle
        }
        view.onChange = { [weak self] change in
            self?.applySettingsChange(change)
        }
        view.onReset = { [weak self, weak view] in
            guard let self else { return }
            PanelSettings.resetToDefaults()
            self.notificationCoordinator.updateSettings(PanelSettings.notifications)
            self.usageStore.setEnabledProviders(PanelSettings.enabledUsageProviders)
            self.systemStatsStore.setRefreshInterval(
                PanelSettings.systemStatsRefreshInterval)
            self.systemStatsStore.setMetrics(PanelSettings.systemStatsMetrics)
            self.serviceMonitorStore.updateConfiguration(
                endpoints: PanelSettings.serviceMonitorEndpoints,
                refreshInterval: PanelSettings.serviceMonitorRefreshInterval)
            self.weatherStore.updateConfiguration(
                location: PanelSettings.weatherLocation,
                unit: PanelSettings.weatherTemperatureUnit,
                refreshInterval: PanelSettings.weatherRefreshInterval)
            self.scheduleStore.updateConfiguration(
                selectedCalendarIDs: PanelSettings.scheduleCalendarIDs,
                selectedReminderListIDs: PanelSettings.scheduleReminderListIDs,
                includeAllDay: PanelSettings.scheduleIncludesAllDay,
                includeReminders: PanelSettings.scheduleIncludesReminders,
                refreshInterval: PanelSettings.scheduleRefreshInterval)
            self.batteryStore.setRefreshInterval(PanelSettings.batteryRefreshInterval)
            self.networkStore.setRefreshInterval(PanelSettings.networkRefreshInterval)
            self.projectPulseStore.updateConfiguration(
                PanelSettings.projectPulseConfiguration)
            self.focusTimerStore.updateSettings(PanelSettings.focusTimerSettings)
            self.focusTimerStore.replaceSession(PanelSettings.focusTimerSession)
            self.applyCornerRadius()
            self.applyTintOpacity()
            self.applyFont()
            for controller in self.readOnlyDeckPanelControllers { controller.applySettings() }
            self.applyPanelVisibility()
            view?.setValues(self.currentSettingsValues)
            self.resizeFocusedTerminalIfNeeded()
        }
        view.onCancel = { [weak self] in
            self?.closeSettingsPanel()
        }

        let settingsPanelWindow = KeyablePanel(
            contentRect: NSRect(
                origin: settingsOrigin(anchor: anchor, size: SettingsPanelView.preferredSize),
                size: SettingsPanelView.preferredSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        settingsPanelWindow.title = pane.windowTitle
        settingsPanelWindow.contentMinSize = SettingsPanelView.preferredSize
        settingsPanelWindow.level = .floating
        settingsPanelWindow.isOpaque = true
        settingsPanelWindow.backgroundColor = .windowBackgroundColor
        settingsPanelWindow.hidesOnDeactivate = false
        settingsPanelWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        settingsPanelWindow.isReleasedWhenClosed = false
        settingsPanelWindow.delegate = self
        settingsPanelWindow.contentView = view
        settingsPanelWindow.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        settingsPanelWindow.standardWindowButton(.zoomButton)?.isEnabled = false
        settingsPanelWindow.setAccessibilityLabel("DockDeck Settings")

        settingsPanelRestoresTerminalFocus = restoreTerminalFocus
        settingsPanel = settingsPanelWindow
        NSApp.activate(ignoringOtherApps: true)
        settingsPanelWindow.makeKeyAndOrderFront(nil)
    }

    private var currentSettingsValues: SettingsPanelValues {
        SettingsPanelValues(
            deckConfiguration: PanelSettings.deckConfiguration,
            notifications: PanelSettings.notifications,
            terminal: TerminalSettingsState(
                focusWidthMultiplier: PanelSettings.focusWidthMultiplier,
                focusHeightMultiplier: PanelSettings.focusHeightMultiplier,
                fontName: PanelSettings.fontName ?? TerminalTheme.defaultFontName),
            usage: UsageSettingsState(
                enabledProviders: PanelSettings.enabledUsageProviders,
                fontName: PanelSettings.usageFontName ?? TerminalTheme.defaultFontName,
                fontSize: PanelSettings.usageFontSize,
                displayMode: PanelSettings.usageDisplayMode,
                textColor: PanelSettings.usageTextColor,
                showsPace: PanelSettings.usageShowsPace),
            systemStats: SystemStatsSettingsState(
                refreshInterval: PanelSettings.systemStatsRefreshInterval,
                metrics: PanelSettings.systemStatsMetrics),
            serviceMonitor: ServiceMonitorSettingsState(
                endpoints: PanelSettings.serviceMonitorEndpoints,
                refreshInterval: PanelSettings.serviceMonitorRefreshInterval),
            weather: WeatherSettingsState(
                location: PanelSettings.weatherLocation,
                temperatureUnit: PanelSettings.weatherTemperatureUnit,
                refreshInterval: PanelSettings.weatherRefreshInterval),
            schedule: ScheduleSettingsState(
                calendarIDs: PanelSettings.scheduleCalendarIDs,
                reminderListIDs: PanelSettings.scheduleReminderListIDs,
                includeAllDay: PanelSettings.scheduleIncludesAllDay,
                includeReminders: PanelSettings.scheduleIncludesReminders,
                refreshInterval: PanelSettings.scheduleRefreshInterval),
            clock: ClockSettingsState(
                timeZoneIdentifier: PanelSettings.clockTimeZoneIdentifier,
                hourFormat: PanelSettings.clockHourFormat),
            battery: BatterySettingsState(
                refreshInterval: PanelSettings.batteryRefreshInterval),
            network: NetworkSettingsState(
                refreshInterval: PanelSettings.networkRefreshInterval),
            projectPulse: PanelSettings.projectPulseConfiguration,
            focusTimer: PanelSettings.focusTimerSettings,
            appearance: AppearanceSettingsState(
                cornerRadius: PanelSettings.cornerRadius,
                tintOpacity: PanelSettings.tintOpacity
                    ?? currentTheme.panelTintColor.alphaComponent))
    }

    private func applySettingsChange(_ change: SettingsPanelChange) {
        switch change {
        case .deck(let configuration):
            let previousTerminalSide = PanelSettings.deckConfiguration.side(containing: .terminal)
            PanelSettings.deckConfiguration = configuration
            if let terminalSide = configuration.side(containing: .terminal),
                terminalSide != previousTerminalSide
            {
                collapsedFrame = nil
                PanelSettings.setActiveModule(.terminal, on: terminalSide)
            }
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
            applyPanelVisibility()
        case .notifications(let settings):
            let wasEnabled = PanelSettings.notifications.enabled
            PanelSettings.notifications = settings
            notificationCoordinator.updateSettings(settings)
            if settings.enabled, !wasEnabled {
                notificationCoordinator.requestAuthorization()
            }
            notificationCoordinator.observeUsage(usageStore.providers)
            notificationCoordinator.observeServices(serviceMonitorStore.items)
            notificationCoordinator.observeBattery(batteryStore.snapshot)
        case .terminal(.focusSize(let width, let height)):
            PanelSettings.focusWidthMultiplier = width
            PanelSettings.focusHeightMultiplier = height
            resizeFocusedTerminalIfNeeded()
        case .terminal(.font(let name)):
            PanelSettings.fontName = name
            applyFont()
        case .usage(.displayMode(let mode)):
            PanelSettings.usageDisplayMode = mode
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        case .usage(.providers(let providers)):
            PanelSettings.enabledUsageProviders = providers
            usageStore.setEnabledProviders(providers)
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        case .usage(.font(let name)):
            PanelSettings.usageFontName = name
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        case .usage(.fontSize(let size)):
            PanelSettings.usageFontSize = size
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        case .usage(.textColor(let color)):
            PanelSettings.usageTextColor = color
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        case .usage(.showsPace(let showsPace)):
            PanelSettings.usageShowsPace = showsPace
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        case .systemStats(.refreshInterval(let interval)):
            PanelSettings.systemStatsRefreshInterval = interval
            systemStatsStore.setRefreshInterval(interval)
        case .systemStats(.metrics(let metrics)):
            PanelSettings.systemStatsMetrics = metrics
            systemStatsStore.setMetrics(metrics)
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        case .serviceMonitor(.endpoints(let endpoints)):
            PanelSettings.serviceMonitorEndpoints = endpoints
            serviceMonitorStore.updateConfiguration(
                endpoints: endpoints,
                refreshInterval: PanelSettings.serviceMonitorRefreshInterval)
        case .serviceMonitor(.refreshInterval(let interval)):
            PanelSettings.serviceMonitorRefreshInterval = interval
            serviceMonitorStore.updateConfiguration(
                endpoints: PanelSettings.serviceMonitorEndpoints,
                refreshInterval: interval)
        case .weather(.location(let location)):
            PanelSettings.weatherLocation = location
            applyWeatherConfiguration()
        case .weather(.temperatureUnit(let unit)):
            PanelSettings.weatherTemperatureUnit = unit
            applyWeatherConfiguration()
        case .weather(.refreshInterval(let interval)):
            PanelSettings.weatherRefreshInterval = interval
            applyWeatherConfiguration()
        case .schedule(.calendarIDs(let identifiers)):
            PanelSettings.scheduleCalendarIDs = identifiers
            applyScheduleConfiguration()
        case .schedule(.reminderListIDs(let identifiers)):
            PanelSettings.scheduleReminderListIDs = identifiers
            applyScheduleConfiguration()
        case .schedule(.includeAllDay(let includeAllDay)):
            PanelSettings.scheduleIncludesAllDay = includeAllDay
            applyScheduleConfiguration()
        case .schedule(.includeReminders(let includeReminders)):
            PanelSettings.scheduleIncludesReminders = includeReminders
            applyScheduleConfiguration()
        case .schedule(.refreshInterval(let interval)):
            PanelSettings.scheduleRefreshInterval = interval
            applyScheduleConfiguration()
        case .clock(.timeZoneIdentifier(let identifier)):
            PanelSettings.clockTimeZoneIdentifier = identifier
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        case .clock(.hourFormat(let format)):
            PanelSettings.clockHourFormat = format
            for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        case .battery(.refreshInterval(let interval)):
            PanelSettings.batteryRefreshInterval = interval
            batteryStore.setRefreshInterval(interval)
        case .network(.refreshInterval(let interval)):
            PanelSettings.networkRefreshInterval = interval
            networkStore.setRefreshInterval(interval)
        case .projectPulse(.configuration(let configuration)):
            PanelSettings.projectPulseConfiguration = configuration
            projectPulseStore.updateConfiguration(configuration)
        case .focusTimer(.settings(let settings)):
            PanelSettings.focusTimerSettings = settings
            focusTimerStore.updateSettings(settings)
        case .appearance(.cornerRadius(let radius)):
            PanelSettings.cornerRadius = radius
            applyCornerRadius()
        case .appearance(.tintOpacity(let opacity)):
            PanelSettings.tintOpacity = opacity
            applyTintOpacity()
        }
    }

    private func applyWeatherConfiguration() {
        weatherStore.updateConfiguration(
            location: PanelSettings.weatherLocation,
            unit: PanelSettings.weatherTemperatureUnit,
            refreshInterval: PanelSettings.weatherRefreshInterval)
    }

    private func applyScheduleConfiguration() {
        scheduleStore.updateConfiguration(
            selectedCalendarIDs: PanelSettings.scheduleCalendarIDs,
            selectedReminderListIDs: PanelSettings.scheduleReminderListIDs,
            includeAllDay: PanelSettings.scheduleIncludesAllDay,
            includeReminders: PanelSettings.scheduleIncludesReminders,
            refreshInterval: PanelSettings.scheduleRefreshInterval)
    }

    private func closeSettingsPanel() {
        settingsPanel?.close()
    }

    func settingsPanelDidClose(_ window: NSWindow) {
        guard window === settingsPanel else { return }
        let restoreTerminalFocus = settingsPanelRestoresTerminalFocus
        settingsPanel = nil
        settingsPanelRestoresTerminalFocus = false

        guard restoreTerminalFocus, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.makeFirstResponder(self.terminalView)
        }
    }

    private func settingsOrigin(anchor: NSWindow, size: NSSize) -> NSPoint {
        let host = anchor.screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let inset: CGFloat = 12
        let x = min(
            max(host.midX - size.width / 2, host.minX + inset),
            host.maxX - size.width - inset)
        let y = min(
            max(host.midY - size.height / 2, host.minY + inset),
            host.maxY - size.height - inset)
        return NSPoint(x: x, y: y)
    }

    func applyCornerRadius() {
        terminalPanelController.applyCornerRadius()
        for controller in readOnlyDeckPanelControllers { controller.applyCornerRadius() }
    }

    func applyTintOpacity() {
        applyTerminalAppearance()
        for controller in readOnlyDeckPanelControllers { controller.applyTheme(currentTheme) }
    }

    func applyFont() {
        let font = TerminalTheme.font(named: PanelSettings.fontName)
        terminalView.font = font
        terminalView.frame = TerminalLayout.contentFrame(
            in: NSRect(origin: .zero, size: panel.frame.size), font: font)
    }

    func applyPanelOrder() {
        collapsedFrame = nil
        isFrozen = false
        refreshCoarseCaches()
        runEvaluation()
    }

    func applyPanelVisibility() {
        isFrozen = false
        synchronizeModuleRuntimes()
        if !PanelSettings.enabledPanels.contains(.terminal) {
            terminalPanelMode = .docked
            expansionScreenID = nil
            terminalPanelController.setResizable(false)
            if panel.isVisible { panel.orderOut(nil) }
        }
        for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        for side in PanelSide.allCases where PanelSettings.activeModule(on: side) == nil {
            hideReadOnlyDeck(on: side, reason: "disabled in settings")
        }
        refreshCoarseCaches()
        runEvaluation()
    }
}
