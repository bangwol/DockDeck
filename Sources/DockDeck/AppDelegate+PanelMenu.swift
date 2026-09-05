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
        menu.addItem(withTitle: "Open Project in Terminal.app…",
            action: #selector(openProjectInTerminalApp(_:)), keyEquivalent: "")
        let restartReason = NSMenuItem(title: terminalPanelController.lastRestartReason, action: nil, keyEquivalent: "")
        restartReason.isEnabled = false
        menu.addItem(restartReason)
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

    @objc func openProjectInTerminalApp(_ sender: Any?) {
        let configuration = PanelSettings.projectPulseConfiguration
        var folder = configuration.source == .local
            ? configuration.repositoryPath.flatMap(TerminalProjectFolder.existingURL) : nil
        if folder == nil {
            let picker = NSOpenPanel()
            picker.title = "Open Folder in Terminal.app"
            picker.canChooseFiles = false
            picker.canChooseDirectories = true
            picker.allowsMultipleSelection = false
            guard picker.runModal() == .OK, let url = picker.url else { return }
            folder = TerminalProjectFolder.existingURL(url.path)
        }
        guard let folder, let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: .init()) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Could not open the folder in Terminal.app"
                alert.informativeText = "Check that the folder and Terminal.app are available."
                alert.runModal()
            }
        }
    }
}

enum TerminalProjectFolder {
    static func existingURL(_ path: String) -> URL? {
        guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4_096 else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
