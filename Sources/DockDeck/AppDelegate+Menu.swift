import Cocoa

extension AppDelegate {
    func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "Toggle Expanded", action: #selector(toggleExpanded(_:)), keyEquivalent: "e"
        )
        appMenu.addItem(
            withTitle: "Switch Theme", action: #selector(toggleThemePicker(_:)), keyEquivalent: "t"
        )
        appMenu.addItem(
            withTitle: "Refresh Usage", action: #selector(refreshUsage(_:)), keyEquivalent: "r"
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
        refreshCoarseCaches()
        let presence = resolveDockPresence()

        if isExpanded {
            isExpanded = false
            expansionScreenID = nil
            if let target = collapseTarget(for: presence) {
                showTerminal(target, animated: true)
            } else {
                panel.orderOut(nil)
            }
        } else {
            isFocusExpanded = false
            isExpanded = true
            let screen = expansionScreen(fallingBackTo: presence?.host)
            expansionScreenID = screen.flatMap(displayID(of:))
            if let screen {
                showTerminal(expandedFrame(on: screen), animated: true)
            }
        }
        if let presence, case .concealed = presence {
            hideQuota()
        } else if let presence, let frame = quotaFrame(for: presence) {
            if !quotaPanel.isVisible { quotaPanel.orderFrontRegardless() }
            applyQuotaFrame(frame)
        } else {
            hideQuota()
        }
        debugLog("expand", "isExpanded=\(isExpanded) screen=\(describe(expansionScreenID))")
        updateFallbackHintVisibility()
    }

    @objc func refreshUsage(_ sender: Any?) {
        usageStore.refresh()
    }
}
