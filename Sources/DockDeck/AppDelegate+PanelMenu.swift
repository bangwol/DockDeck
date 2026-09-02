import Cocoa

extension AppDelegate {
    @objc func showPanelMenu(_ sender: Any?) {
        guard let button = sender as? NSButton else { return }
        if PanelSettings.deckConfiguration.enabled.contains(.usage) {
            usageStore.refreshClaudeUsageIfDue()
        }

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
        let configuration = PanelSettings.deckConfiguration
        if let side = configuration.side(containing: .terminal) {
            let modules = configuration.enabledModules(on: side)
            if modules.count > 1 {
                let next = NSMenuItem(
                    title: "Show Next Module",
                    action: #selector(showNextTerminalDeckModule(_:)), keyEquivalent: "")
                next.target = self
                menu.addItem(next)

                let moduleItem = NSMenuItem(title: "Modules", action: nil, keyEquivalent: "")
                let moduleMenu = NSMenu(title: "Modules")
                for module in modules {
                    guard let definition = PanelModuleRegistry.definition(for: module) else {
                        continue
                    }
                    let item = NSMenuItem(
                        title: definition.title,
                        action: #selector(selectTerminalDeckModule(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = module.rawValue
                    item.state = module == .terminal ? .on : .off
                    moduleMenu.addItem(item)
                }
                moduleItem.submenu = moduleMenu
                menu.addItem(moduleItem)
            }
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
