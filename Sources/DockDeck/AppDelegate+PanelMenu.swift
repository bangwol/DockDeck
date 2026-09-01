import Cocoa

extension AppDelegate {
    @objc func showPanelMenu(_ sender: Any?) {
        guard let button = sender as? NSButton else { return }

        let menu = NSMenu()

        menu.addItem(
            NSMenuItem(
                title: isExpanded ? "Collapse" : "Expand",
                action: #selector(toggleExpanded(_:)), keyEquivalent: "e"))
        menu.addItem(
            NSMenuItem(
                title: "Theme: \(currentTheme.name)",
                action: #selector(toggleThemePicker(_:)), keyEquivalent: "t"))
        menu.addItem(
            NSMenuItem(
                title: "Settings…",
                action: #selector(toggleSettingsPanel(_:)), keyEquivalent: ""))
        menu.addItem(
            NSMenuItem(
                title: "Refresh Usage",
                action: #selector(refreshUsage(_:)), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit DockDeck",
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.popUp(positioning: nil, at: .zero, in: button)
    }
}
