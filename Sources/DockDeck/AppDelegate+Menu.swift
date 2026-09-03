import Cocoa

extension AppDelegate {
    func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "DockDeck")
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About DockDeck", action: #selector(showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Toggle Large Terminal", action: #selector(toggleExpanded(_:)),
            keyEquivalent: "e"
        )
        appMenu.addItem(
            withTitle: "Switch Theme", action: #selector(toggleThemePicker(_:)), keyEquivalent: "t"
        )
        appMenu.addItem(
            withTitle: "Settings…", action: #selector(toggleSettingsPanel(_:)), keyEquivalent: ","
        )
        appMenu.addItem(
            withTitle: "Refresh Modules & Layout", action: #selector(refreshModules(_:)),
            keyEquivalent: "r"
        )
        appMenu.addItem(
            withTitle: "Close Window", action: #selector(closeFrontWindow(_:)), keyEquivalent: "w"
        )
        appMenu.addItem(
            withTitle: "Quit DockDeck", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc func toggleExpanded(_ sender: Any?) {
        let configuration = PanelSettings.deckConfiguration
        guard configuration.contains(.terminal),
            let terminalSide = configuration.side(containing: .terminal)
        else { return }
        PanelSettings.setActiveModule(.terminal, on: terminalSide)
        for controller in readOnlyDeckPanelControllers { controller.applySettings() }
        refreshCoarseCaches()
        let presence = resolveDockPresence()

        if isExpanded {
            returnTerminalToDock()
            return
        }

        terminalPanelMode = .large
        let screen = expansionScreen(fallingBackTo: presence?.host)
        expansionScreenID = screen.flatMap(displayID(of:))
        if let screen {
            showTerminal(expandedFrame(on: screen), animated: true)
        }
        terminalPanelController.setResizable(false)
        applyTerminalAppearance()
        if let presence, case .concealed = presence {
            hideReadOnlyDecks()
        } else if let presence {
            showPanels(for: presence)
        } else {
            hideReadOnlyDecks()
        }
        debugLog("expand", "isExpanded=\(isExpanded) screen=\(describe(expansionScreenID))")
        updateFallbackHintVisibility()
    }

    @objc func refreshModules(_ sender: Any?) {
        let enabled = Set(PanelSettings.enabledReadOnlyModules)
        if enabled.contains(.usage) { usageStore.refresh() }
        if enabled.contains(.systemStats) { systemStatsStore.refresh() }
        if enabled.contains(.serviceMonitor) { serviceMonitorStore.refresh() }
        if enabled.contains(.weather) { weatherStore.refresh() }
        if enabled.contains(.schedule) { scheduleStore.refreshAuthorization() }
        if enabled.contains(.battery) { batteryStore.refresh() }
        if enabled.contains(.network) { networkStore.refresh() }
        if enabled.contains(.projectPulse) { projectPulseStore.refresh() }
        if enabled.contains(.githubInbox) { githubInboxStore.refresh() }
        if enabled.contains(.docker) { dockerStore.refresh() }
        if enabled.contains(.customTile) { customTileStore.refresh() }
        if enabled.contains(.focusTimer) { focusTimerStore.refresh() }
        refreshCoarseCaches()
        startTrackingTimer()
        runEvaluation()
    }

    /// Only the Settings window and theme picker are closable; the Dock panels ignore ⌘W
    /// instead of beeping through NSWindow.performClose(_:).
    @objc func closeFrontWindow(_ sender: Any?) {
        if let settingsPanel, settingsPanel.isKeyWindow {
            settingsPanel.close()
        } else if themePickerPanel?.isKeyWindow == true {
            toggleThemePicker(nil)
        }
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }
}
