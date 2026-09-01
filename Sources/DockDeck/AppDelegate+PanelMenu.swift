import Cocoa

extension AppDelegate {
    @objc func showPanelMenu(_ sender: Any?) {
        guard let button = sender as? NSButton else { return }

        let menu = NSMenu()

        menu.addItem(
            NSMenuItem(
                title: isExpanded ? "Return Terminal to Dock" : "Open Large Terminal",
                action: #selector(toggleExpanded(_:)), keyEquivalent: "e"))
        menu.addItem(
            NSMenuItem(
                title: "Theme: \(currentTheme.name)",
                action: #selector(toggleThemePicker(_:)), keyEquivalent: "t"))
        menu.addItem(
            NSMenuItem(
                title: "Settings…",
                action: #selector(toggleSettingsPanel(_:)), keyEquivalent: ""))
        if PanelSettings.enabledReadOnlyModules.count > 1 {
            menu.addItem(
                NSMenuItem(
                    title: "Show Next Module",
                    action: #selector(showNextReadOnlyModule(_:)), keyEquivalent: ""))
        }
        if readOnlyDeckPanelController.activeModule == .usage {
            menu.addItem(
                NSMenuItem(
                    title: PanelSettings.usageDisplayMode == .remaining
                        ? "Show Used Values" : "Show Remaining Values",
                    action: #selector(toggleUsageDisplayMode(_:)), keyEquivalent: ""))
        }
        menu.addItem(
            NSMenuItem(
                title: PanelSettings.panelOrder == .terminalLeft
                    ? "Move Terminal to Right" : "Move Terminal to Left",
                action: #selector(swapPanelSides(_:)), keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: "Refresh Modules & Layout",
                action: #selector(refreshModules(_:)), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "About DockDeck",
                action: #selector(showAbout(_:)), keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: "Quit DockDeck",
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.popUp(positioning: nil, at: .zero, in: button)
    }
}
