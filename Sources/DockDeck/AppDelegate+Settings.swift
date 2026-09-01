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
            anchor: terminalEnabled ? panel : quotaPanel,
            restoreTerminalFocus: terminalEnabled)
    }

    @objc func openUsageSettings(_ sender: Any?) {
        if let settingsPanel {
            (settingsPanel.contentView as? SettingsPanelView)?.selectPane(.usage)
            settingsPanel.makeKeyAndOrderFront(nil)
            return
        }
        presentSettingsPanel(pane: .usage, anchor: quotaPanel, restoreTerminalFocus: false)
    }

    @objc func toggleUsageDisplayMode(_ sender: Any?) {
        PanelSettings.usageDisplayMode =
            PanelSettings.usageDisplayMode == .remaining ? .used : .remaining
        quotaPanelController.applySettings()
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
            deckConfiguration: PanelSettings.deckConfiguration,
            cornerRadius: PanelSettings.cornerRadius,
            tintOpacity: PanelSettings.tintOpacity ?? currentTheme.panelTintColor.alphaComponent,
            focusWidthMultiplier: PanelSettings.focusWidthMultiplier,
            focusHeightMultiplier: PanelSettings.focusHeightMultiplier,
            fontNames: TerminalTheme.installedFontNames,
            selectedTerminalFontName: PanelSettings.fontName ?? TerminalTheme.defaultFontName,
            selectedUsageFontName: PanelSettings.usageFontName ?? TerminalTheme.defaultFontName,
            usageFontSize: PanelSettings.usageFontSize,
            usageDisplayMode: PanelSettings.usageDisplayMode,
            usageTextColor: PanelSettings.usageTextColor)

        view.onPaneChange = { [weak self] pane in
            UserDefaults.standard.set(pane.rawValue, forKey: AppPreferences.settingsPaneKey)
            self?.settingsPanel?.title = pane.windowTitle
        }
        view.onDeckConfigurationChange = { [weak self] configuration in
            PanelSettings.deckConfiguration = configuration
            self?.applyPanelVisibility()
        }
        view.onCornerRadiusChange = { [weak self] radius in
            PanelSettings.cornerRadius = radius
            self?.applyCornerRadius()
        }
        view.onTintOpacityChange = { [weak self] opacity in
            PanelSettings.tintOpacity = opacity
            self?.applyTintOpacity()
        }
        view.onTerminalFontChange = { [weak self] name in
            PanelSettings.fontName = name
            self?.applyFont()
        }
        view.onFocusSizeChange = { [weak self] width, height in
            PanelSettings.focusWidthMultiplier = width
            PanelSettings.focusHeightMultiplier = height
            self?.resizeFocusedTerminalIfNeeded()
        }
        view.onUsageDisplayModeChange = { [weak self] mode in
            PanelSettings.usageDisplayMode = mode
            self?.quotaPanelController.applySettings()
        }
        view.onUsageFontChange = { [weak self] name in
            PanelSettings.usageFontName = name
            self?.quotaPanelController.applySettings()
        }
        view.onUsageFontSizeChange = { [weak self] size in
            PanelSettings.usageFontSize = size
            self?.quotaPanelController.applySettings()
        }
        view.onUsageTextColorChange = { [weak self] color in
            PanelSettings.usageTextColor = color
            self?.quotaPanelController.applySettings()
        }
        view.onReset = { [weak self, weak view] in
            guard let self else { return }
            PanelSettings.resetToDefaults()
            self.applyCornerRadius()
            self.applyTintOpacity()
            self.applyFont()
            self.quotaPanelController.applySettings()
            self.applyPanelVisibility()
            view?.setValues(
                deckConfiguration: PanelSettings.deckConfiguration,
                cornerRadius: PanelSettings.cornerRadius,
                tintOpacity: self.currentTheme.panelTintColor.alphaComponent,
                focusWidthMultiplier: PanelSettings.focusWidthMultiplier,
                focusHeightMultiplier: PanelSettings.focusHeightMultiplier,
                terminalFontName: TerminalTheme.defaultFontName,
                usageFontName: TerminalTheme.defaultFontName,
                usageFontSize: PanelSettings.usageFontSize,
                usageDisplayMode: PanelSettings.usageDisplayMode,
                usageTextColor: PanelSettings.usageTextColor)
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
        quotaPanelController.applyCornerRadius()
    }

    func applyTintOpacity() {
        applyTerminalAppearance()
        quotaPanelController.applyTheme(currentTheme)
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
        if !PanelSettings.enabledPanels.contains(.terminal) {
            terminalPanelMode = .docked
            expansionScreenID = nil
            terminalPanelController.setResizable(false)
            if panel.isVisible { panel.orderOut(nil) }
        }
        if !PanelSettings.enabledPanels.contains(.usage) {
            hideQuota(reason: "disabled in settings")
        }
        refreshCoarseCaches()
        runEvaluation()
    }
}
