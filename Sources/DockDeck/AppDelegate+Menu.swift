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
        guard PanelSettings.enabledPanels.contains(.terminal) else { return }
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
            hideReadOnlyDeck()
        } else if let presence, let frame = readOnlyDeckFrame(for: presence) {
            showReadOnlyDeck(frame)
        } else {
            hideReadOnlyDeck()
        }
        debugLog("expand", "isExpanded=\(isExpanded) screen=\(describe(expansionScreenID))")
        updateFallbackHintVisibility()
    }

    @objc func refreshModules(_ sender: Any?) {
        if PanelSettings.enabledReadOnlyModules.contains(.usage) { usageStore.refresh() }
        if PanelSettings.enabledReadOnlyModules.contains(.systemStats) {
            systemStatsStore.refresh()
        }
        if PanelSettings.enabledReadOnlyModules.contains(.serviceMonitor) {
            serviceMonitorStore.refresh()
        }
        if PanelSettings.enabledReadOnlyModules.contains(.weather) {
            weatherStore.refresh()
        }
        refreshCoarseCaches()
        startTrackingTimer()
        runEvaluation()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }
}
