import Cocoa

extension AppDelegate {
    @objc func toggleSettingsPanel(_ sender: Any?) {
        let terminalEnabled = PanelSettings.enabledPanels.contains(.terminal)
        toggleSettingsPanel(
            anchor: terminalEnabled ? panel : quotaPanel,
            restoreTerminalFocus: terminalEnabled)
    }

    @objc func openUsageSettings(_ sender: Any?) {
        toggleSettingsPanel(anchor: quotaPanel, restoreTerminalFocus: false)
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

    private func toggleSettingsPanel(anchor: NSWindow, restoreTerminalFocus: Bool) {
        if settingsPanel != nil {
            closeSettingsPanel(restoreTerminalFocus: restoreTerminalFocus)
            return
        }

        let view = SettingsPanelView(
            cornerRadius: PanelSettings.cornerRadius,
            tintOpacity: PanelSettings.tintOpacity ?? currentTheme.panelTintColor.alphaComponent,
            focusWidthMultiplier: PanelSettings.focusWidthMultiplier,
            focusHeightMultiplier: PanelSettings.focusHeightMultiplier,
            fontNames: TerminalTheme.installedFontNames,
            selectedTerminalFontName: PanelSettings.fontName ?? TerminalTheme.defaultFontName,
            selectedUsageFontName: PanelSettings.usageFontName ?? TerminalTheme.defaultFontName,
            usageFontSize: PanelSettings.usageFontSize,
            usageDisplayMode: PanelSettings.usageDisplayMode,
            usageTextColor: PanelSettings.usageTextColor,
            panelOrder: PanelSettings.panelOrder,
            enabledPanels: PanelSettings.enabledPanels)

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
        view.onPanelOrderChange = { [weak self] order in
            PanelSettings.panelOrder = order
            self?.applyPanelOrder()
        }
        view.onEnabledPanelsChange = { [weak self] enabledPanels in
            PanelSettings.enabledPanels = enabledPanels
            self?.applyPanelVisibility()
        }
        view.onReset = { [weak self, weak view] in
            guard let self else { return }
            PanelSettings.resetToDefaults()
            self.applyCornerRadius()
            self.applyTintOpacity()
            self.applyFont()
            self.quotaPanelController.applySettings()
            self.applyPanelOrder()
            view?.setValues(
                cornerRadius: PanelSettings.cornerRadius,
                tintOpacity: self.currentTheme.panelTintColor.alphaComponent,
                focusWidthMultiplier: PanelSettings.focusWidthMultiplier,
                focusHeightMultiplier: PanelSettings.focusHeightMultiplier,
                terminalFontName: TerminalTheme.defaultFontName,
                usageFontName: TerminalTheme.defaultFontName,
                usageFontSize: PanelSettings.usageFontSize,
                usageDisplayMode: PanelSettings.usageDisplayMode,
                usageTextColor: PanelSettings.usageTextColor,
                panelOrder: PanelSettings.panelOrder,
                enabledPanels: PanelSettings.enabledPanels)
            self.resizeFocusedTerminalIfNeeded()
        }
        view.onCancel = { [weak self] in
            self?.closeSettingsPanel(restoreTerminalFocus: restoreTerminalFocus)
        }

        let settingsPanelWindow = KeyablePanel(
            contentRect: NSRect(
                origin: settingsOrigin(anchor: anchor, size: view.frame.size),
                size: view.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        settingsPanelWindow.level = NSWindow.Level(rawValue: Int(kCGDockWindowLevel) + 2)
        settingsPanelWindow.isOpaque = false
        settingsPanelWindow.backgroundColor = .clear
        settingsPanelWindow.hidesOnDeactivate = false
        settingsPanelWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        settingsPanelWindow.contentView = view

        settingsPanelWindow.makeKeyAndOrderFront(nil)
        settingsPanelWindow.makeFirstResponder(view)
        settingsPanel = settingsPanelWindow
    }

    private func closeSettingsPanel(restoreTerminalFocus: Bool) {
        settingsPanel?.orderOut(nil)
        settingsPanel = nil
        guard restoreTerminalFocus, PanelSettings.enabledPanels.contains(.terminal) else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(terminalView)
    }

    private func settingsOrigin(anchor: NSWindow, size: NSSize) -> NSPoint {
        let host = anchor.screen?.frame ?? NSScreen.screens.first?.frame ?? .zero
        let inset: CGFloat = 8
        let desiredX = anchor.frame.midX - size.width / 2
        let x = min(max(desiredX, host.minX + inset), host.maxX - size.width - inset)
        let desiredY = anchor.frame.maxY + inset
        let y = min(
            max(desiredY, host.minY + inset),
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
        if !PanelSettings.enabledPanels.contains(.terminal) {
            isExpanded = false
            isFocusExpanded = false
            isFrozen = false
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
