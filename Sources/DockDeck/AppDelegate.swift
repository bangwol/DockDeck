import ApplicationServices
import Cocoa
import CoreGraphics
import SwiftTerm

enum TerminalPanelMode {
    case docked
    case focused
    case large
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let accessibilityWarmupDelay: TimeInterval = 3

    var terminalPanelController: TerminalPanelController!
    var leftReadOnlyDeckPanelController: ReadOnlyDeckPanelController!
    var rightReadOnlyDeckPanelController: ReadOnlyDeckPanelController!
    lazy var usageStore = UsageStore { [weak self] message in
        self?.debugLog("usage", message)
    }
    lazy var systemStatsStore = SystemStatsStore()
    lazy var serviceMonitorStore = ServiceMonitorStore()
    lazy var weatherStore = WeatherStore()
    lazy var scheduleStore = ScheduleStore()
    lazy var clockStore = ClockStore()
    lazy var batteryStore = BatteryStore()
    lazy var networkStore = NetworkStore()
    lazy var dockCoordinator = DockCoordinator { [weak self] channel, message in
        self?.debugLog(channel, message)
    }
    let moduleRuntimeCoordinator = ModuleRuntimeCoordinator()

    var panel: KeyablePanel { terminalPanelController.panel }
    var readOnlyDeckPanelControllers: [ReadOnlyDeckPanelController] {
        [leftReadOnlyDeckPanelController, rightReadOnlyDeckPanelController].compactMap { $0 }
    }
    var readOnlyDeckPanels: [NSPanel] { readOnlyDeckPanelControllers.map(\.panel) }
    func readOnlyDeckPanelController(on side: PanelSide) -> ReadOnlyDeckPanelController {
        side == .left ? leftReadOnlyDeckPanelController : rightReadOnlyDeckPanelController
    }
    var terminalView: LocalProcessTerminalView { terminalPanelController.terminalView }
    var menuButton: NSButton { terminalPanelController.menuButton }
    var trackingTimer: Timer!
    var terminalLocalMouseMonitor: Any?
    var terminalGlobalMouseMonitor: Any?
    var currentTheme = Theme.theme(
        id: UserDefaults.standard.string(forKey: AppPreferences.themeIDKey) ?? "")
    var themePickerPanel: KeyablePanel?
    var settingsPanel: KeyablePanel?
    var settingsPanelRestoresTerminalFocus = false

    var terminalPanelMode: TerminalPanelMode = .docked
    var isExpanded: Bool { terminalPanelMode == .large }
    var isFocusExpanded: Bool { terminalPanelMode == .focused }
    var isFrozen = false
    var wasConcealed = false
    var expansionScreenID: CGDirectDisplayID?
    var collapsedFrame: NSRect?
    /// Target of an in-flight animated terminal frame change. AppKit reports animator-driven
    /// resizes as live resizes, so this distinguishes them from a user dragging an edge.
    var animatingTerminalFrame: NSRect?

    var accessibilityTrusted = false
    var hintPanel: NSPanel?
    var hintTintView: NSView?
    var hintLabel: NSTextField?
    var hintDismissed = false

    var lastPresenceUntracked = true
    var tickCount = 0
    var lastDebugLine: [String: String] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        PanelSettings.migratePanelDeckIfNeeded()
        let hasLaunchedBefore = UserDefaults.standard.bool(
            forKey: AppPreferences.hasLaunchedBeforeKey)
        accessibilityTrusted = dockCoordinator.isAccessibilityTrusted
        UserDefaults.standard.set(true, forKey: AppPreferences.hasLaunchedBeforeKey)

        setUpMainMenu()

        refreshCoarseCaches()
        let initialPresence = resolveDockPresence()
        let fallbackScreen = mainDisplayScreen() ?? NSScreen.screens.first
        let fallbackFrames = fallbackScreen.map {
            dockCoordinator.fallbackFrames(on: $0)
        }
        let initialFrames =
            initialPresence.map { collapsedFrames(for: $0) }
            ?? fallbackFrames
            ?? DockPanelFrames(
                terminal: NSRect(
                    x: 0, y: 0, width: Self.fallbackWidth, height: Self.fallbackHeight),
                quota: nil)
        let terminalSide = PanelSettings.deckConfiguration.side(containing: .terminal) ?? .left
        let initialTerminalFrame =
            initialFrames.frame(on: terminalSide)
            ?? NSRect(x: 0, y: 0, width: Self.fallbackWidth, height: Self.fallbackHeight)
        let initialLeftFrame =
            initialFrames.frame(on: .left)
            ?? initialTerminalFrame
        let initialRightFrame =
            initialFrames.frame(on: .right)
            ?? NSRect(
                x: initialTerminalFrame.maxX + DockPanelLayout.gap,
                y: initialTerminalFrame.minY,
                width: DockPanelLayout.fallbackPanelWidth,
                height: initialTerminalFrame.height)
        collapsedFrame = initialFrames.frame(on: terminalSide)
        lastPresenceUntracked = initialPresence?.isUntracked ?? true

        terminalPanelController = TerminalPanelController(
            initialFrame: initialTerminalFrame,
            theme: currentTheme,
            menuTarget: self,
            menuAction: #selector(showPanelMenu(_:)),
            onShellEvent: { [weak self] message in
                self?.debugLog("shell", message)
            })
        usageStore.setEnabledProviders(PanelSettings.enabledUsageProviders)
        leftReadOnlyDeckPanelController = ReadOnlyDeckPanelController(
            initialFrame: initialLeftFrame,
            theme: currentTheme,
            usageStore: usageStore,
            systemStatsStore: systemStatsStore,
            serviceMonitorStore: serviceMonitorStore,
            weatherStore: weatherStore,
            scheduleStore: scheduleStore,
            clockStore: clockStore,
            batteryStore: batteryStore,
            networkStore: networkStore,
            menuTarget: self,
            side: .left,
            onSelectionChange: { [weak self] side in
                self?.deckSelectionDidChange(on: side)
            })
        rightReadOnlyDeckPanelController = ReadOnlyDeckPanelController(
            initialFrame: initialRightFrame,
            theme: currentTheme,
            usageStore: usageStore,
            systemStatsStore: systemStatsStore,
            serviceMonitorStore: serviceMonitorStore,
            weatherStore: weatherStore,
            scheduleStore: scheduleStore,
            clockStore: clockStore,
            batteryStore: batteryStore,
            networkStore: networkStore,
            menuTarget: self,
            side: .right,
            onSelectionChange: { [weak self] side in
                self?.deckSelectionDidChange(on: side)
            })
        panel.delegate = self
        registerModuleRuntimes()
        synchronizeModuleRuntimes()

        if case .concealed? = initialPresence {
            debugLog("visibility", "launching concealed (auto-hiding Dock is off screen)")
        } else {
            showPanels(in: initialFrames)
        }
        panel.makeFirstResponder(terminalView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(terminalPanelDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification, object: panel)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceApplicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        terminalLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            if event.window === self?.panel {
                self?.terminalPanelController.ensureShellRunning()
                self?.expandTerminalForFocus()
            } else {
                self?.collapseTerminalAfterFocus()
            }
            return event
        }
        terminalGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapseTerminalAfterFocus()
            }
        }

        startTrackingTimer()

        if !accessibilityTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.accessibilityWarmupDelay) {
                [weak self] in
                guard let self else { return }
                self.refreshCoarseCaches()
                guard !self.accessibilityTrusted else { return }

                self.installFallbackHintIfNeeded()
                self.updateFallbackHintVisibility()
                guard !hasLaunchedBefore else { return }

                let promptOptions =
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(promptOptions)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let terminalLocalMouseMonitor { NSEvent.removeMonitor(terminalLocalMouseMonitor) }
        if let terminalGlobalMouseMonitor { NSEvent.removeMonitor(terminalGlobalMouseMonitor) }
        trackingTimer?.invalidate()
        moduleRuntimeCoordinator.stopAll()
    }

    private func registerModuleRuntimes() {
        moduleRuntimeCoordinator.register(
            .terminal,
            start: { [weak self] in self?.terminalPanelController.startShell() },
            stop: { [weak self] in self?.terminalPanelController.stopShell() })
        moduleRuntimeCoordinator.register(
            .usage,
            start: { [weak self] in self?.usageStore.start() },
            stop: { [weak self] in self?.usageStore.stop() })
        moduleRuntimeCoordinator.register(
            .systemStats,
            start: { [weak self] in self?.systemStatsStore.start() },
            stop: { [weak self] in self?.systemStatsStore.stop() })
        moduleRuntimeCoordinator.register(
            .serviceMonitor,
            start: { [weak self] in self?.serviceMonitorStore.start() },
            stop: { [weak self] in self?.serviceMonitorStore.stop() })
        moduleRuntimeCoordinator.register(
            .weather,
            start: { [weak self] in self?.weatherStore.start() },
            stop: { [weak self] in self?.weatherStore.stop() })
        moduleRuntimeCoordinator.register(
            .schedule,
            start: { [weak self] in self?.scheduleStore.start() },
            stop: { [weak self] in self?.scheduleStore.stop() })
        moduleRuntimeCoordinator.register(
            .clock,
            start: { [weak self] in self?.clockStore.start() },
            stop: { [weak self] in self?.clockStore.stop() })
        moduleRuntimeCoordinator.register(
            .battery,
            start: { [weak self] in self?.batteryStore.start() },
            stop: { [weak self] in self?.batteryStore.stop() })
        moduleRuntimeCoordinator.register(
            .network,
            start: { [weak self] in self?.networkStore.start() },
            stop: { [weak self] in self?.networkStore.stop() })
    }

    func synchronizeModuleRuntimes() {
        moduleRuntimeCoordinator.synchronize(
            enabledModules: PanelSettings.deckConfiguration.enabled)
    }
}
