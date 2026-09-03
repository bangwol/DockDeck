import Cocoa
import SwiftUI

private final class ReadOnlyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum ReadOnlyModuleDetailLayout {
    static let initialSize = NSSize(width: 520, height: 240)
    static let minimumSize = NSSize(width: 420, height: 190)
}

enum DeckScrollDirection: Equatable {
    case previous
    case next

    static func resolved(deltaX: CGFloat, deltaY: CGFloat) -> Self? {
        guard abs(deltaY) > abs(deltaX), deltaY != 0 else { return nil }
        return deltaY > 0 ? .previous : .next
    }
}

final class ReadOnlyDeckPanelController:
    NSObject, NSMenuDelegate, NSGestureRecognizerDelegate, NSWindowDelegate
{
    private static let usageRefreshClickDebounce: TimeInterval = 0.75

    let panel: NSPanel
    let side: PanelSide

    private let surfaceView: PanelSurfaceView
    private let services: PanelModuleServices
    private let presentation: ReadOnlyDeckPresentation
    private weak var menuTarget: AnyObject?
    private let onSelectionChange: (PanelSide) -> Void
    private let onAutoSlideStateChange: () -> Void
    private var lastScrollSelectionTime: TimeInterval = 0
    private var lastUsageRefreshClickTime: TimeInterval?
    private var appliedModule: PanelModuleID?
    private var detailPanel: NSPanel?
    private var isMenuOpen = false

    init(
        initialFrame: NSRect,
        theme: Theme,
        services: PanelModuleServices,
        menuTarget: AnyObject,
        side: PanelSide = .right,
        onSelectionChange: @escaping (PanelSide) -> Void = { _ in },
        onAutoSlideStateChange: @escaping () -> Void = {}
    ) {
        self.services = services
        self.menuTarget = menuTarget
        self.side = side
        self.onSelectionChange = onSelectionChange
        self.onAutoSlideStateChange = onAutoSlideStateChange
        let presentation = ReadOnlyDeckPresentation(
            activeModule: PanelSettings.activeModule(on: side), theme: theme)
        self.presentation = presentation

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
                services: services,
                presentation: presentation))
        hostingView.frame = surfaceView.bounds
        hostingView.autoresizingMask = [.width, .height]
        surfaceView.contentContainer.addSubview(hostingView)

        let menu = NSMenu(title: "Modules")
        surfaceView.menu = menu
        hostingView.menu = menu
        panel.contentView = surfaceView

        self.panel = panel
        self.surfaceView = surfaceView
        super.init()
        surfaceView.onScrollWheel = { [weak self] event in
            self?.handleScrollWheel(event) ?? false
        }
        let doubleClick = NSClickGestureRecognizer(
            target: self, action: #selector(showDetailFromGesture(_:)))
        doubleClick.numberOfClicksRequired = 2
        let singleClick = NSClickGestureRecognizer(
            target: self, action: #selector(refreshUsageFromGesture(_:)))
        singleClick.numberOfClicksRequired = 1
        singleClick.delegate = self
        hostingView.addGestureRecognizer(doubleClick)
        hostingView.addGestureRecognizer(singleClick)
        menu.delegate = self
        applySettings()
    }

    var activeModule: PanelModuleID? { PanelSettings.activeModule(on: side) }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let click = gestureRecognizer as? NSClickGestureRecognizer,
            let otherClick = otherGestureRecognizer as? NSClickGestureRecognizer
        else { return false }
        return click.numberOfClicksRequired == 1 && otherClick.numberOfClicksRequired > 1
    }

    func applyTheme(_ theme: Theme) {
        presentation.setTheme(theme)
        surfaceView.apply(theme: theme, presentation: .compact)
    }

    func applySettings() {
        render(
            activeModule: PanelSettings.activeModule(on: side),
            direction: .next,
            showsIndicator: false)
    }

    /// Dock-tracking ticks call this up to ten times per second; rebuild the module view
    /// only when the resolved active module changed since the last render.
    @discardableResult
    func synchronizeActiveModule() -> Bool {
        let activeModule = PanelSettings.activeModule(on: side)
        guard activeModule != appliedModule else { return false }
        render(activeModule: activeModule, direction: .next, showsIndicator: false)
        return true
    }

    private func render(
        activeModule: PanelModuleID?, direction: DeckTransitionDirection,
        showsIndicator: Bool
    ) {
        appliedModule = activeModule
        PanelSettings.setActiveModule(activeModule, on: side)
        let title = activeModule.flatMap { PanelModuleRegistry.definition(for: $0)?.title }
            ?? "Modules"
        panel.title = "DockDeck \(title)"
        panel.setAccessibilityLabel("DockDeck \(title)")
        detailPanel?.title = "DockDeck — \(title)"
        presentation.select(
            activeModule,
            direction: direction,
            enabledModules: PanelSettings.enabledModules(on: side),
            showsIndicator: showsIndicator)
    }

    func select(
        _ module: PanelModuleID, direction: DeckTransitionDirection = .next
    ) {
        select(module, direction: direction, notifiesSelection: true)
    }

    func selectForAutoSlide(_ module: PanelModuleID) {
        select(module, direction: .next, notifiesSelection: false)
    }

    private func select(
        _ module: PanelModuleID, direction: DeckTransitionDirection,
        notifiesSelection: Bool
    ) {
        guard PanelSettings.enabledModules(on: side).contains(module) else { return }
        render(activeModule: module, direction: direction, showsIndicator: true)
        if notifiesSelection { onSelectionChange(side) }
    }

    func selectNext() {
        guard
            let next = ReadOnlyDeckSelection.next(
                after: activeModule,
                enabledModules: PanelSettings.enabledModules(on: side))
        else { return }
        select(next, direction: .next)
    }

    func selectPrevious() {
        guard
            let previous = ReadOnlyDeckSelection.previous(
                before: activeModule,
                enabledModules: PanelSettings.enabledModules(on: side))
        else { return }
        select(previous, direction: .previous)
    }

    func applyCornerRadius() {
        surfaceView.applyCornerRadius()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        onAutoSlideStateChange()
        menu.removeAllItems()
        if activeModule == .usage { services.usage.refreshClaudeUsageIfDue() }

        addItem(
            to: menu,
            title: "Settings…",
            action: #selector(AppDelegate.openReadOnlyModuleSettings(_:)),
            representedObject: side.rawValue)
        let detailItem = NSMenuItem(
            title: "Open Detail…", action: #selector(showDetailFromMenu(_:)),
            keyEquivalent: "")
        detailItem.target = self
        detailItem.isEnabled = activeModule != nil
        menu.addItem(detailItem)

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

        if activeModule == .focusTimer {
            menu.addItem(.separator())
            let toggle = NSMenuItem(
                title: services.focusTimer.snapshot.mode == .running ? "Pause Timer" : "Start Timer",
                action: #selector(toggleFocusTimer(_:)), keyEquivalent: "")
            toggle.target = self
            menu.addItem(toggle)
            let reset = NSMenuItem(
                title: "Reset Timer", action: #selector(resetFocusTimer(_:)), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
            let skip = NSMenuItem(
                title: "Skip to \(services.focusTimer.snapshot.phase.next.title.capitalized)",
                action: #selector(skipFocusTimer(_:)), keyEquivalent: "")
            skip.target = self
            menu.addItem(skip)
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

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        onAutoSlideStateChange()
    }

    @objc private func selectNextFromMenu(_ sender: Any?) {
        selectNext()
    }

    @objc private func showDetailFromMenu(_ sender: Any?) {
        showDetail()
    }

    @objc private func showDetailFromGesture(_ sender: NSClickGestureRecognizer) {
        guard sender.state == .ended else { return }
        showDetail()
    }

    @objc private func refreshUsageFromGesture(_ sender: NSClickGestureRecognizer) {
        guard sender.state == .ended else { return }
        refreshUsageIfActive()
    }

    @discardableResult
    func refreshUsageIfActive(
        at currentUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        guard activeModule == .usage else { return false }
        if let lastUsageRefreshClickTime,
            currentUptime - lastUsageRefreshClickTime
                < Self.usageRefreshClickDebounce
        {
            return false
        }
        lastUsageRefreshClickTime = currentUptime
        services.usage.refresh()
        return true
    }

    func showDetail() {
        guard let activeModule,
            let definition = PanelModuleRegistry.definition(for: activeModule)
        else { return }
        if let detailPanel {
            detailPanel.title = "DockDeck — \(definition.title)"
            NSApp.activate(ignoringOtherApps: true)
            detailPanel.makeKeyAndOrderFront(nil)
            onAutoSlideStateChange()
            return
        }

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: ReadOnlyModuleDetailLayout.initialSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "DockDeck — \(definition.title)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = ReadOnlyModuleDetailLayout.minimumSize
        let frameName = "DockDeck.ModuleDetail.\(side.rawValue)"
        let restoredFrame = window.setFrameUsingName(frameName)
        window.setFrameAutosaveName(frameName)
        window.contentView = NSHostingView(
            rootView: ReadOnlyModuleDetailView(
                services: services, presentation: presentation))
        if !restoredFrame { window.center() }
        detailPanel = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onAutoSlideStateChange()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            window === detailPanel
        else { return }
        DispatchQueue.main.async { [weak self] in self?.onAutoSlideStateChange() }
    }

    var detailWindowForTesting: NSPanel? { detailPanel }

    @objc private func selectModuleFromMenu(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
            let rawValue = item.representedObject as? String
        else { return }
        select(PanelModuleID(rawValue: rawValue))
    }

    @objc private func toggleFocusTimer(_ sender: Any?) {
        services.focusTimer.toggle()
    }

    @objc private func resetFocusTimer(_ sender: Any?) {
        services.focusTimer.reset()
    }

    @objc private func skipFocusTimer(_ sender: Any?) {
        services.focusTimer.skip()
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

    var blocksAutoSlideInteraction: Bool {
        isMenuOpen || detailPanel?.isVisible == true || !panel.isVisible
            || panel.frame.contains(NSEvent.mouseLocation)
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
