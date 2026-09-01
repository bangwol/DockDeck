import Cocoa

extension AppDelegate {
    @objc func toggleSettingsPanel(_ sender: Any?) {
        if let settingsPanel {
            settingsPanel.makeKeyAndOrderFront(nil)
            return
        }

        let terminalEnabled = PanelSettings.enabledPanels.contains(.terminal)
        presentSettingsPanel(
            pane: savedSettingsPane,
            anchor: terminalEnabled ? panel : readOnlyDeckPanel,
            restoreTerminalFocus: terminalEnabled)
    }

    @objc func openReadOnlyModuleSettings(_ sender: Any?) {
        let pane = readOnlyDeckPanelController.activeModule
            .flatMap { PanelModuleRegistry.definition(for: $0)?.settingsPane } ?? .decks
        if let settingsPanel {
            (settingsPanel.contentView as? SettingsPanelView)?.selectPane(pane)
            settingsPanel.makeKeyAndOrderFront(nil)
            return
        }
        presentSettingsPanel(pane: pane, anchor: readOnlyDeckPanel, restoreTerminalFocus: false)
    }

    @objc func showNextReadOnlyModule(_ sender: Any?) {
        readOnlyDeckPanelController.selectNext()
    }

    @objc func selectReadOnlyModule(_ sender: Any?) {
        guard
            let item = sender as? NSMenuItem,
            let rawValue = item.representedObject as? String
        else { return }
        readOnlyDeckPanelController.select(PanelModuleID(rawValue: rawValue))
    }

    @objc func toggleUsageDisplayMode(_ sender: Any?) {
        PanelSettings.usageDisplayMode =
            PanelSettings.usageDisplayMode == .remaining ? .used : .remaining
        readOnlyDeckPanelController.applySettings()
    }

    @objc func swapPanelSides(_ sender: Any?) {
        PanelSettings.panelOrder =
            PanelSettings.panelOrder == .terminalLeft ? .terminalRight : .terminalLeft
        applyPanelOrder()
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
            self.usageStore.setEnabledProviders(PanelSettings.enabledUsageProviders)
            self.systemStatsStore.setRefreshInterval(
                PanelSettings.systemStatsRefreshInterval)
            self.serviceMonitorStore.updateConfiguration(
                endpoints: PanelSettings.serviceMonitorEndpoints,
                refreshInterval: PanelSettings.serviceMonitorRefreshInterval)
            self.weatherStore.updateConfiguration(
                location: PanelSettings.weatherLocation,
                unit: PanelSettings.weatherTemperatureUnit,
                refreshInterval: PanelSettings.weatherRefreshInterval)
            self.scheduleStore.updateConfiguration(
                selectedCalendarIDs: PanelSettings.scheduleCalendarIDs,
                includeAllDay: PanelSettings.scheduleIncludesAllDay,
                refreshInterval: PanelSettings.scheduleRefreshInterval)
            self.applyCornerRadius()
            self.applyTintOpacity()
            self.applyFont()
            self.readOnlyDeckPanelController.applySettings()
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
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        settingsPanelWindow.title = pane.windowTitle
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
        settingsPanelWindow.makeKeyAndOrderFront(nil)
    }

    private var currentSettingsValues: SettingsPanelValues {
        SettingsPanelValues(
            deckConfiguration: PanelSettings.deckConfiguration,
            terminal: TerminalSettingsState(
                focusWidthMultiplier: PanelSettings.focusWidthMultiplier,
                focusHeightMultiplier: PanelSettings.focusHeightMultiplier,
                fontName: PanelSettings.fontName ?? TerminalTheme.defaultFontName),
            usage: UsageSettingsState(
                enabledProviders: PanelSettings.enabledUsageProviders,
                fontName: PanelSettings.usageFontName ?? TerminalTheme.defaultFontName,
                fontSize: PanelSettings.usageFontSize,
                displayMode: PanelSettings.usageDisplayMode,
                textColor: PanelSettings.usageTextColor),
            systemStats: SystemStatsSettingsState(
                refreshInterval: PanelSettings.systemStatsRefreshInterval),
            serviceMonitor: ServiceMonitorSettingsState(
                endpoints: PanelSettings.serviceMonitorEndpoints,
                refreshInterval: PanelSettings.serviceMonitorRefreshInterval),
            weather: WeatherSettingsState(
                location: PanelSettings.weatherLocation,
                temperatureUnit: PanelSettings.weatherTemperatureUnit,
                refreshInterval: PanelSettings.weatherRefreshInterval),
            schedule: ScheduleSettingsState(
                calendarIDs: PanelSettings.scheduleCalendarIDs,
                includeAllDay: PanelSettings.scheduleIncludesAllDay,
                refreshInterval: PanelSettings.scheduleRefreshInterval),
            appearance: AppearanceSettingsState(
                cornerRadius: PanelSettings.cornerRadius,
                tintOpacity: PanelSettings.tintOpacity
                    ?? currentTheme.panelTintColor.alphaComponent))
    }

    private func applySettingsChange(_ change: SettingsPanelChange) {
        switch change {
        case .deck(let configuration):
            PanelSettings.deckConfiguration = configuration
            readOnlyDeckPanelController.applySettings()
            applyPanelVisibility()
        case .terminal(.focusSize(let width, let height)):
            PanelSettings.focusWidthMultiplier = width
            PanelSettings.focusHeightMultiplier = height
            resizeFocusedTerminalIfNeeded()
        case .terminal(.font(let name)):
            PanelSettings.fontName = name
            applyFont()
        case .usage(.displayMode(let mode)):
            PanelSettings.usageDisplayMode = mode
            readOnlyDeckPanelController.applySettings()
        case .usage(.providers(let providers)):
            PanelSettings.enabledUsageProviders = providers
            usageStore.setEnabledProviders(providers)
            readOnlyDeckPanelController.applySettings()
        case .usage(.font(let name)):
            PanelSettings.usageFontName = name
            readOnlyDeckPanelController.applySettings()
        case .usage(.fontSize(let size)):
            PanelSettings.usageFontSize = size
            readOnlyDeckPanelController.applySettings()
        case .usage(.textColor(let color)):
            PanelSettings.usageTextColor = color
            readOnlyDeckPanelController.applySettings()
        case .systemStats(.refreshInterval(let interval)):
            PanelSettings.systemStatsRefreshInterval = interval
            systemStatsStore.setRefreshInterval(interval)
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
        case .schedule(.includeAllDay(let includeAllDay)):
            PanelSettings.scheduleIncludesAllDay = includeAllDay
            applyScheduleConfiguration()
        case .schedule(.refreshInterval(let interval)):
            PanelSettings.scheduleRefreshInterval = interval
            applyScheduleConfiguration()
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
            includeAllDay: PanelSettings.scheduleIncludesAllDay,
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

        guard restoreTerminalFocus, PanelSettings.enabledPanels.contains(.terminal) else { return }
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
        readOnlyDeckPanelController.applyCornerRadius()
    }

    func applyTintOpacity() {
        applyTerminalAppearance()
        readOnlyDeckPanelController.applyTheme(currentTheme)
    }

    func applyFont() {
        let font = TerminalTheme.font(named: PanelSettings.fontName)
        terminalView.font = font
        terminalView.frame = TerminalLayout.contentFrame(
            in: NSRect(origin: .zero, size: panel.frame.size), font: font)
    }

    func applyPanelOrder() {
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
        readOnlyDeckPanelController.applySettings()
        if PanelSettings.enabledReadOnlyModules.isEmpty {
            hideReadOnlyDeck(reason: "disabled in settings")
        }
        refreshCoarseCaches()
        runEvaluation()
    }
}
