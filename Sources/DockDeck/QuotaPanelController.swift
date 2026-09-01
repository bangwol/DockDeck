import Cocoa
import SwiftUI

private final class ReadOnlyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class QuotaPanelController: NSObject, NSMenuDelegate {
    let panel: NSPanel

    private let surfaceView: PanelSurfaceView
    private let hostingView: NSHostingView<QuotaPanelView>
    private let store: UsageStore
    private let displayModeItem: NSMenuItem
    private let panelOrderItem: NSMenuItem
    private var theme: Theme

    init(initialFrame: NSRect, theme: Theme, store: UsageStore, menuTarget: AnyObject) {
        self.store = store
        self.theme = theme

        let panel = ReadOnlyPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = NSWindow.Level(rawValue: Int(kCGDockWindowLevel) + 1)
        panel.title = "DockDeck Usage"
        panel.setAccessibilityLabel("DockDeck Usage")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let surfaceView = PanelSurfaceView(
            frame: NSRect(origin: .zero, size: initialFrame.size), theme: theme)

        let hostingView = NSHostingView(
            rootView: QuotaPanelView(
                store: store, theme: theme, configuration: .current))
        hostingView.frame = surfaceView.bounds
        hostingView.autoresizingMask = [.width, .height]
        surfaceView.contentContainer.addSubview(hostingView)

        let menu = NSMenu(title: "Usage")
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(AppDelegate.openUsageSettings(_:)),
            keyEquivalent: "")
        let displayModeItem = NSMenuItem(
            title: "", action: #selector(AppDelegate.toggleUsageDisplayMode(_:)),
            keyEquivalent: "")
        let panelOrderItem = NSMenuItem(
            title: "", action: #selector(AppDelegate.swapPanelSides(_:)), keyEquivalent: "")
        let refreshItem = NSMenuItem(
            title: "Refresh Usage & Layout", action: #selector(AppDelegate.refreshUsage(_:)),
            keyEquivalent: "")
        for item in [settingsItem, displayModeItem, panelOrderItem, refreshItem] {
            item.target = menuTarget
        }
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(displayModeItem)
        menu.addItem(panelOrderItem)
        menu.addItem(.separator())
        menu.addItem(refreshItem)
        surfaceView.menu = menu
        hostingView.menu = menu

        panel.contentView = surfaceView
        self.panel = panel
        self.surfaceView = surfaceView
        self.hostingView = hostingView
        self.displayModeItem = displayModeItem
        self.panelOrderItem = panelOrderItem
        super.init()
        menu.delegate = self
    }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        surfaceView.apply(theme: theme, presentation: .compact)
        applySettings()
    }

    func applySettings() {
        hostingView.rootView = QuotaPanelView(
            store: store, theme: theme, configuration: .current)
    }

    func applyCornerRadius() {
        surfaceView.applyCornerRadius()
    }

    func menuWillOpen(_ menu: NSMenu) {
        displayModeItem.title =
            PanelSettings.usageDisplayMode == .remaining
            ? "Show Used Values" : "Show Remaining Values"
        panelOrderItem.title =
            PanelSettings.panelOrder == .terminalLeft
            ? "Move Terminal to Right" : "Move Terminal to Left"
    }
}
