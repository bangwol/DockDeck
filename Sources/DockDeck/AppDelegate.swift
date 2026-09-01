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
    var quotaPanelController: QuotaPanelController!
    lazy var usageStore = UsageStore { [weak self] message in
        self?.debugLog("usage", message)
    }
    lazy var dockCoordinator = DockCoordinator { [weak self] channel, message in
        self?.debugLog(channel, message)
    }

    var panel: KeyablePanel { terminalPanelController.panel }
    var quotaPanel: NSPanel { quotaPanelController.panel }
    var terminalView: LocalProcessTerminalView { terminalPanelController.terminalView }
    var menuButton: NSButton { terminalPanelController.menuButton }
    var trackingTimer: Timer!
    var terminalLocalMouseMonitor: Any?
    var terminalGlobalMouseMonitor: Any?
    var currentTheme = Theme.theme(
        id: UserDefaults.standard.string(forKey: AppPreferences.themeIDKey) ?? "")
    var themePickerPanel: KeyablePanel?
    var settingsPanel: KeyablePanel?

    var terminalPanelMode: TerminalPanelMode = .docked
    var isExpanded: Bool { terminalPanelMode == .large }
    var isFocusExpanded: Bool { terminalPanelMode == .focused }
    var isFrozen = false
    var wasConcealed = false
    var expansionScreenID: CGDirectDisplayID?
    var collapsedFrame: NSRect?

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
            dockCoordinator.fallbackFrames(on: $0).ordered(PanelSettings.panelOrder)
        }
        let initialFrames =
            initialPresence.map { collapsedFrames(for: $0) }
            ?? fallbackFrames
            ?? DockPanelFrames(
                terminal: NSRect(
                    x: 0, y: 0, width: Self.fallbackWidth, height: Self.fallbackHeight),
                quota: nil)
        let initialTerminalFrame =
            initialFrames.terminal
            ?? NSRect(x: 0, y: 0, width: Self.fallbackWidth, height: Self.fallbackHeight)
        let initialQuotaFrame =
            initialFrames.quota
            ?? NSRect(
                x: initialTerminalFrame.maxX + DockPanelLayout.gap,
                y: initialTerminalFrame.minY,
                width: DockPanelLayout.fallbackPanelWidth,
                height: initialTerminalFrame.height)
        collapsedFrame = initialFrames.terminal
        lastPresenceUntracked = initialPresence?.isUntracked ?? true

        terminalPanelController = TerminalPanelController(
            initialFrame: initialTerminalFrame,
            theme: currentTheme,
            menuTarget: self,
            menuAction: #selector(showPanelMenu(_:)),
            onShellEvent: { [weak self] message in
                self?.debugLog("shell", message)
            })
        quotaPanelController = QuotaPanelController(
            initialFrame: initialQuotaFrame,
            theme: currentTheme,
            store: usageStore,
            menuTarget: self)
        panel.delegate = self

        if case .concealed? = initialPresence {
            debugLog("visibility", "launching concealed (auto-hiding Dock is off screen)")
        } else {
            let enabledPanels = PanelSettings.enabledPanels
            if enabledPanels.contains(.terminal), initialFrames.terminal != nil {
                panel.orderFrontRegardless()
            }
            if enabledPanels.contains(.usage), initialFrames.quota != nil {
                quotaPanel.orderFrontRegardless()
            }
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

        terminalPanelController.startShell()
        usageStore.start()

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
        terminalPanelController?.stopShell()
        usageStore.stop()
    }
}
