import Cocoa
import SwiftUI

private final class ReadOnlyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ReadOnlyDeckPanelController: NSObject, NSMenuDelegate {
    let panel: NSPanel

    private let surfaceView: PanelSurfaceView
    private let hostingView: NSHostingView<ReadOnlyDeckPanelView>
    private let usageStore: UsageStore
    private let systemStatsStore: SystemStatsStore
    private let serviceMonitorStore: ServiceMonitorStore
    private let weatherStore: WeatherStore
    private let scheduleStore: ScheduleStore
    private let clockStore: ClockStore
    private let batteryStore: BatteryStore
    private let networkStore: NetworkStore
    private weak var menuTarget: AnyObject?
    private var theme: Theme

    init(
        initialFrame: NSRect,
        theme: Theme,
        usageStore: UsageStore,
        systemStatsStore: SystemStatsStore,
        serviceMonitorStore: ServiceMonitorStore,
        weatherStore: WeatherStore,
        scheduleStore: ScheduleStore,
        clockStore: ClockStore,
        batteryStore: BatteryStore,
        networkStore: NetworkStore,
        menuTarget: AnyObject
    ) {
        self.usageStore = usageStore
        self.systemStatsStore = systemStatsStore
        self.serviceMonitorStore = serviceMonitorStore
        self.weatherStore = weatherStore
        self.scheduleStore = scheduleStore
        self.clockStore = clockStore
        self.batteryStore = batteryStore
        self.networkStore = networkStore
        self.theme = theme
        self.menuTarget = menuTarget

        let panel = ReadOnlyPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = NSWindow.Level(rawValue: Int(kCGDockWindowLevel) + 1)
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
            rootView: ReadOnlyDeckPanelView(
                usageStore: usageStore,
                systemStatsStore: systemStatsStore,
                serviceMonitorStore: serviceMonitorStore,
                weatherStore: weatherStore,
                scheduleStore: scheduleStore,
                clockStore: clockStore,
                batteryStore: batteryStore,
                networkStore: networkStore,
                activeModule: PanelSettings.activeReadOnlyModule,
                theme: theme))
        hostingView.frame = surfaceView.bounds
        hostingView.autoresizingMask = [.width, .height]
        surfaceView.contentContainer.addSubview(hostingView)

        let menu = NSMenu(title: "Modules")
        surfaceView.menu = menu
        hostingView.menu = menu
        panel.contentView = surfaceView

        self.panel = panel
        self.surfaceView = surfaceView
        self.hostingView = hostingView
        super.init()
        menu.delegate = self
        applySettings()
    }

    var activeModule: PanelModuleID? { PanelSettings.activeReadOnlyModule }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        surfaceView.apply(theme: theme, presentation: .compact)
        applySettings()
    }

    func applySettings() {
        let activeModule = PanelSettings.activeReadOnlyModule
        PanelSettings.activeReadOnlyModule = activeModule
        let title = activeModule.flatMap { PanelModuleRegistry.definition(for: $0)?.title }
            ?? "Modules"
        panel.title = "DockDeck \(title)"
        panel.setAccessibilityLabel("DockDeck \(title)")
        hostingView.rootView = ReadOnlyDeckPanelView(
            usageStore: usageStore,
            systemStatsStore: systemStatsStore,
            serviceMonitorStore: serviceMonitorStore,
            weatherStore: weatherStore,
            scheduleStore: scheduleStore,
            clockStore: clockStore,
            batteryStore: batteryStore,
            networkStore: networkStore,
            activeModule: activeModule,
            theme: theme)
    }

    func select(_ module: PanelModuleID) {
        guard PanelSettings.enabledReadOnlyModules.contains(module) else { return }
        PanelSettings.activeReadOnlyModule = module
        applySettings()
    }

    func selectNext() {
        guard
            let next = ReadOnlyDeckSelection.next(
                after: activeModule,
                enabledModules: PanelSettings.enabledReadOnlyModules)
        else { return }
        select(next)
    }

    func applyCornerRadius() {
        surfaceView.applyCornerRadius()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        addItem(
            to: menu,
            title: "Settings…",
            action: #selector(AppDelegate.openReadOnlyModuleSettings(_:)))

        let enabledModules = PanelSettings.enabledReadOnlyModules
        if enabledModules.count > 1 {
            addItem(
                to: menu,
                title: "Show Next Module",
                action: #selector(AppDelegate.showNextReadOnlyModule(_:)))

            let moduleItem = NSMenuItem(title: "Modules", action: nil, keyEquivalent: "")
            let moduleMenu = NSMenu(title: "Modules")
            for module in enabledModules {
                guard let definition = PanelModuleRegistry.definition(for: module) else { continue }
                let item = NSMenuItem(
                    title: definition.title,
                    action: #selector(AppDelegate.selectReadOnlyModule(_:)),
                    keyEquivalent: "")
                item.target = menuTarget
                item.representedObject = module.rawValue
                item.state = module == activeModule ? .on : .off
                moduleMenu.addItem(item)
            }
            moduleItem.submenu = moduleMenu
            menu.addItem(moduleItem)
        }

        if activeModule == .usage {
            menu.addItem(.separator())
            addItem(
                to: menu,
                title: PanelSettings.usageDisplayMode == .remaining
                    ? "Show Used Values" : "Show Remaining Values",
                action: #selector(AppDelegate.toggleUsageDisplayMode(_:)))
        }

        menu.addItem(.separator())
        addItem(
            to: menu,
            title: PanelSettings.panelOrder == .terminalLeft
                ? "Move Terminal to Right" : "Move Terminal to Left",
            action: #selector(AppDelegate.swapPanelSides(_:)))
        addItem(
            to: menu,
            title: "Refresh Modules & Layout",
            action: #selector(AppDelegate.refreshModules(_:)))
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = menuTarget
        menu.addItem(item)
    }
}
