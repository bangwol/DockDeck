import Cocoa
import SwiftUI

private final class ReadOnlyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum DeckScrollDirection: Equatable {
    case previous
    case next

    static func resolved(deltaX: CGFloat, deltaY: CGFloat) -> Self? {
        guard abs(deltaY) > abs(deltaX), deltaY != 0 else { return nil }
        return deltaY > 0 ? .previous : .next
    }
}

final class ReadOnlyDeckPanelController: NSObject, NSMenuDelegate {
    let panel: NSPanel
    let side: PanelSide

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
    private let onSelectionChange: (PanelSide) -> Void
    private var lastScrollSelectionTime: TimeInterval = 0

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
        menuTarget: AnyObject,
        side: PanelSide = .right,
        onSelectionChange: @escaping (PanelSide) -> Void = { _ in }
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
        self.side = side
        self.onSelectionChange = onSelectionChange

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
                activeModule: PanelSettings.activeModule(on: side),
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
        surfaceView.onScrollWheel = { [weak self] event in
            self?.handleScrollWheel(event) ?? false
        }
        menu.delegate = self
        applySettings()
    }

    var activeModule: PanelModuleID? { PanelSettings.activeModule(on: side) }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        surfaceView.apply(theme: theme, presentation: .compact)
        applySettings()
    }

    func applySettings() {
        let activeModule = PanelSettings.activeModule(on: side)
        PanelSettings.setActiveModule(activeModule, on: side)
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
        guard PanelSettings.enabledModules(on: side).contains(module) else { return }
        PanelSettings.setActiveModule(module, on: side)
        applySettings()
        onSelectionChange(side)
    }

    func selectNext() {
        guard
            let next = ReadOnlyDeckSelection.next(
                after: activeModule,
                enabledModules: PanelSettings.enabledModules(on: side))
        else { return }
        select(next)
    }

    func selectPrevious() {
        guard
            let previous = ReadOnlyDeckSelection.previous(
                before: activeModule,
                enabledModules: PanelSettings.enabledModules(on: side))
        else { return }
        select(previous)
    }

    func applyCornerRadius() {
        surfaceView.applyCornerRadius()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        addItem(
            to: menu,
            title: "Settings…",
            action: #selector(AppDelegate.openReadOnlyModuleSettings(_:)),
            representedObject: side.rawValue)

        let enabledModules = PanelSettings.enabledModules(on: side)
        if enabledModules.count > 1 {
            let nextItem = NSMenuItem(
                title: "Show Next Module", action: #selector(selectNextFromMenu(_:)),
                keyEquivalent: "")
            nextItem.target = self
            menu.addItem(nextItem)

            let moduleItem = NSMenuItem(title: "Modules", action: nil, keyEquivalent: "")
            let moduleMenu = NSMenu(title: "Modules")
            for module in enabledModules {
                guard let definition = PanelModuleRegistry.definition(for: module) else { continue }
                let item = NSMenuItem(
                    title: definition.title,
                    action: #selector(selectModuleFromMenu(_:)),
                    keyEquivalent: "")
                item.target = self
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

    @objc private func selectNextFromMenu(_ sender: Any?) {
        selectNext()
    }

    @objc private func selectModuleFromMenu(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
            let rawValue = item.representedObject as? String
        else { return }
        select(PanelModuleID(rawValue: rawValue))
    }

    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        let enabledModules = PanelSettings.enabledModules(on: side)
        guard enabledModules.count > 1,
            let direction = DeckScrollDirection.resolved(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY)
        else { return false }

        if !event.momentumPhase.isEmpty { return true }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastScrollSelectionTime >= 0.35 else { return true }
        lastScrollSelectionTime = now

        switch direction {
        case .previous: selectPrevious()
        case .next: selectNext()
        }
        return true
    }

    private func addItem(
        to menu: NSMenu, title: String, action: Selector, representedObject: Any? = nil
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = menuTarget
        item.representedObject = representedObject
        menu.addItem(item)
    }
}
