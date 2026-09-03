import ApplicationServices
import Cocoa
import Combine
import CoreGraphics
import SwiftTerm

enum TerminalPanelMode {
    case docked
    case focused
    case large
}

enum TerminalScrollRoute: Equatable {
    case deck
    case terminal

    static func resolved(for mode: TerminalPanelMode) -> Self {
        switch mode {
        case .docked: .deck
        case .focused, .large: .terminal
        }
    }
}

enum TerminalAutoSlidePolicy {
    static func blocksAdvance(
        mode: TerminalPanelMode,
        panelIsVisible: Bool,
        panelIsKey: Bool,
        pointerInside: Bool
    ) -> Bool {
        guard case .docked = mode else { return true }
        return !panelIsVisible || panelIsKey || pointerInside
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let accessibilityWarmupDelay: TimeInterval = 3

    var terminalPanelController: TerminalPanelController!
    var leftReadOnlyDeckPanelController: ReadOnlyDeckPanelController!
    var rightReadOnlyDeckPanelController: ReadOnlyDeckPanelController!
    lazy var usageStore = UsageStore(logger: { [weak self] message in
        self?.debugLog("usage", message)
    })
    lazy var systemStatsStore = SystemStatsStore()
    lazy var serviceMonitorStore = ServiceMonitorStore()
    lazy var weatherStore = WeatherStore()
    lazy var scheduleStore = ScheduleStore()
    lazy var clockStore = ClockStore()
    lazy var batteryStore = BatteryStore()
    lazy var networkStore = NetworkStore()
    lazy var projectPulseStore = ProjectPulseStore()
    lazy var githubInboxStore = GitHubInboxStore()
    lazy var dockerStore = DockerStore()
    lazy var customTileStore = CustomTileStore()
    lazy var diagnosticsStore = DiagnosticsStore(runtimeProvider: { [weak self] in
        self?.moduleRuntimeCoordinator.diagnostics() ?? .empty
    })
    lazy var focusTimerStore = FocusTimerStore(
        settings: PanelSettings.focusTimerSettings,
        session: PanelSettings.focusTimerSession,
        onSessionChange: { PanelSettings.focusTimerSession = $0 },
        onCompletion: { [weak self] phase in
            self?.notificationCoordinator.notifyFocusTimerCompleted(phase)
        })
    lazy var moduleServices = PanelModuleServices(
        usage: usageStore,
        systemStats: systemStatsStore,
        serviceMonitor: serviceMonitorStore,
        weather: weatherStore,
        schedule: scheduleStore,
        clock: clockStore,
        battery: batteryStore,
        network: networkStore,
        projectPulse: projectPulseStore,
        githubInbox: githubInboxStore,
        docker: dockerStore,
        customTile: customTileStore,
        focusTimer: focusTimerStore)
    let notificationCoordinator = DockNotificationCoordinator(
        settings: PanelSettings.notifications)
    lazy var dockCoordinator = DockCoordinator { [weak self] channel, message in
        self?.debugLog(channel, message)
    }
    let moduleRuntimeCoordinator = ModuleRuntimeCoordinator()
    var notificationCancellables: Set<AnyCancellable> = []

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
    var deckAutoSlideTimer: Timer?
    var terminalLocalMouseMonitor: Any?
    var terminalGlobalMouseMonitor: Any?
    var terminalScrollMonitor: Any?
    var lastTerminalDeckScrollSelectionTime: TimeInterval = 0
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
    var usageDisplayAwake = true
    var usageSessionActive = true

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
            },
            onResizeEnd: { [weak self] in
                self?.terminalResizeDidEnd()
            })
        usageStore.setEnabledProviders(PanelSettings.enabledUsageProviders)
        usageStore.setClaudeRefreshMode(PanelSettings.claudeUsageRefreshMode)
        leftReadOnlyDeckPanelController = ReadOnlyDeckPanelController(
            initialFrame: initialLeftFrame,
            theme: currentTheme,
            services: moduleServices,
            menuTarget: self,
            side: .left,
            onSelectionChange: { [weak self] side in
                self?.deckSelectionDidChange(on: side)
            },
            onAutoSlideStateChange: { [weak self] in
                self?.synchronizeDeckAutoSlideTimer()
            })
        rightReadOnlyDeckPanelController = ReadOnlyDeckPanelController(
            initialFrame: initialRightFrame,
            theme: currentTheme,
            services: moduleServices,
            menuTarget: self,
            side: .right,
            onSelectionChange: { [weak self] side in
                self?.deckSelectionDidChange(on: side)
            },
            onAutoSlideStateChange: { [weak self] in
                self?.synchronizeDeckAutoSlideTimer()
            })
        panel.delegate = self
        configureNotifications()
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
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self, selector: #selector(usageDisplayDidSleep(_:)),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspaceNotifications.addObserver(
            self, selector: #selector(usageDisplayDidSleep(_:)),
            name: NSWorkspace.willSleepNotification, object: nil)
        workspaceNotifications.addObserver(
            self, selector: #selector(usageDisplayDidWake(_:)),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspaceNotifications.addObserver(
            self, selector: #selector(usageDisplayDidWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)
        workspaceNotifications.addObserver(
            self, selector: #selector(usageSessionDidResignActive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceNotifications.addObserver(
            self, selector: #selector(usageSessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
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
        terminalScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleTerminalScrollWheel(event) ? nil : event
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange(_:)),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange(_:)),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let terminalLocalMouseMonitor { NSEvent.removeMonitor(terminalLocalMouseMonitor) }
        if let terminalGlobalMouseMonitor { NSEvent.removeMonitor(terminalGlobalMouseMonitor) }
        if let terminalScrollMonitor { NSEvent.removeMonitor(terminalScrollMonitor) }
        trackingTimer?.invalidate()
        deckAutoSlideTimer?.invalidate()
        moduleRuntimeCoordinator.stopAll()
        notificationCancellables.removeAll()
    }

    private func registerModuleRuntimes() {
        moduleRuntimeCoordinator.register(
            .terminal,
            start: { [weak self] in self?.terminalPanelController.startShell() },
            stop: { [weak self] in self?.terminalPanelController.stopShell() },
            suspendsWhenInactive: false)
        for module in PanelModuleID.readOnlyBuiltIns {
            guard let runtime = moduleServices.runtime(for: module) else {
                preconditionFailure("Missing module runtime: \(module.rawValue)")
            }
            moduleRuntimeCoordinator.register(
                module,
                start: { runtime.start() },
                stop: { runtime.stop() },
                updateActivity: { runtime.setRuntimeActivity(
                    $0, lowPowerMode: $1)
                })
        }
    }

    private func configureNotifications() {
        notificationCoordinator.refreshAuthorizationStatus()
        usageStore.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.notificationCoordinator.observeUsage($0) }
            .store(in: &notificationCancellables)
        serviceMonitorStore.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.notificationCoordinator.observeServices($0) }
            .store(in: &notificationCancellables)
        batteryStore.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.notificationCoordinator.observeBattery($0) }
            .store(in: &notificationCancellables)
        systemStatsStore.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.notificationCoordinator.observeSystemStats($0) }
            .store(in: &notificationCancellables)
    }

    func synchronizeModuleRuntimes() {
        let visibleModules = PanelSide.allCases.compactMap {
            PanelSettings.activeModule(on: $0)
        }
        let processInfo = ProcessInfo.processInfo
        let systemActive = usageDisplayAwake && usageSessionActive
        moduleRuntimeCoordinator.synchronize(
            enabledModules: PanelSettings.deckConfiguration.enabled,
            visibleModules: visibleModules,
            lowPowerMode: ModuleRuntimePolicy.isConstrained(
                lowPowerMode: processInfo.isLowPowerModeEnabled,
                thermalState: processInfo.thermalState),
            systemActive: systemActive)
        synchronizeDeckAutoSlideTimer()
    }

    @objc private func powerStateDidChange(_ notification: Notification) {
        synchronizeModuleRuntimes()
    }

    @objc private func usageDisplayDidSleep(_ notification: Notification) {
        usageDisplayAwake = false
        synchronizeModuleRuntimes()
    }

    @objc private func usageDisplayDidWake(_ notification: Notification) {
        usageDisplayAwake = true
        synchronizeModuleRuntimes()
    }

    @objc private func usageSessionDidResignActive(_ notification: Notification) {
        usageSessionActive = false
        synchronizeModuleRuntimes()
    }

    @objc private func usageSessionDidBecomeActive(_ notification: Notification) {
        usageSessionActive = true
        synchronizeModuleRuntimes()
    }
}
