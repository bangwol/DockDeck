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
        appMenu.addItem(withTitle: "Find Module…", action: #selector(showModulePicker(_:)), keyEquivalent: "")
        let profileItem = NSMenuItem(title: "Deck Profiles", action: nil, keyEquivalent: "")
        profileItem.submenu = deckProfilesMenu
        deckProfilesMenu.delegate = self
        appMenu.addItem(profileItem)
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
        synchronizeDeckAutoSlideTimer()
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
        if enabled.contains(.music) { musicStore.refresh() }
        if enabled.contains(.battery) { batteryStore.refresh() }
        if enabled.contains(.localPorts) { moduleServices.localPorts.refresh() }
        if enabled.contains(.projectPulse) { projectPulseStore.refresh() }
        if enabled.contains(.githubInbox) { githubInboxStore.refresh() }
        if enabled.contains(.docker) { dockerStore.refresh() }
        for module in PanelModuleID.customTiles where enabled.contains(module) {
            (moduleServices.runtime(for: module) as? CustomTileStore)?.refresh()
        }
        if enabled.contains(.focusTimer) { focusTimerStore.refresh() }
        refreshCoarseCaches()
        startTrackingTimer()
        runEvaluation()
    }

    @objc func closeFrontWindow(_ sender: Any?) {
        if themePickerPanel?.isKeyWindow == true {
            toggleThemePicker(nil)
            return
        }
        guard let window = NSApp.keyWindow, window !== panel,
            window.styleMask.contains(.closable) else { return }
        window.performClose(sender)
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === deckProfilesMenu else { return }
        menu.removeAllItems()
        for profile in deckProfiles.archive.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectDeckProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id.uuidString
            item.state = profile.configuration.normalized() == PanelSettings.deckConfiguration
                && profile.autoSlide == PanelSettings.deckAutoSlideSettings ? .on : .off
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let manage = NSMenuItem(title: "Manage Profiles…", action: #selector(manageDeckProfiles(_:)), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)
    }

    @objc func selectDeckProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
            let profile = deckProfiles.archive.profiles.first(where: { $0.id.uuidString == id }) else { return }
        applyDeckProfile(profile)
    }

    @objc func manageDeckProfiles(_ sender: Any?) { openSettingsPane(.decks) }
}
