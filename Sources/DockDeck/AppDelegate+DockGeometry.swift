import Cocoa

extension AppDelegate {
    static let fallbackWidth = DockPanelLayout.fallbackPanelWidth
    static let fallbackHeight = DockPanelLayout.fallbackHeight
    static let expandedSizeFraction: CGFloat = 0.75

    func resolveDockPresence() -> DockPresence? {
        dockCoordinator.resolvePresence()
    }

    func terminalFrame(for presence: DockPresence) -> NSRect? {
        if panel.inLiveResize { return panel.frame }
        if isExpanded {
            let screen = expansionScreenID.flatMap(screen(for:)) ?? presence.host
            return expandedFrame(on: screen)
        }
        let collapsed = collapsedFrames(for: presence).terminal
        guard isFocusExpanded, let collapsed else { return collapsed }
        return focusedTerminalFrame(collapsed: collapsed, hostFrame: presence.host.frame)
    }

    func collapsedFrames(for presence: DockPresence) -> DockPanelFrames {
        dockCoordinator.frames(for: presence).ordered(PanelSettings.panelOrder)
    }

    func readOnlyDeckFrame(for presence: DockPresence) -> NSRect? {
        collapsedFrames(for: presence).quota
    }

    func expandedFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = visible.width * Self.expandedSizeFraction
        let height = visible.height * Self.expandedSizeFraction
        let x = visible.minX + (visible.width - width) / 2
        let y = visible.minY + (visible.height - height) / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func fallbackFrame(on screen: NSScreen) -> NSRect {
        dockCoordinator.fallbackFrames(on: screen).ordered(PanelSettings.panelOrder).terminal
            ?? NSRect(
                x: screen.frame.minX, y: screen.frame.minY,
                width: Self.fallbackWidth, height: Self.fallbackHeight)
    }

    func expandTerminalForFocus() {
        guard !isExpanded, !isFocusExpanded else { return }
        terminalPanelMode = .focused
        applyTerminalAppearance()
        refreshCoarseCaches()
        let presence = resolveDockPresence()
        let screen = expansionScreen(fallingBackTo: presence?.host)
        let collapsed = collapsedFrame ?? presence.flatMap { collapsedFrames(for: $0).terminal }
        if let screen, let collapsed {
            setFocusedTerminalResizable(collapsed: collapsed, hostFrame: screen.frame)
            showTerminal(
                focusedTerminalFrame(collapsed: collapsed, hostFrame: screen.frame),
                animated: true)
        }
        updateFallbackHintVisibility()
    }

    @objc func terminalPanelDidResignKey(_ notification: Notification) {
        collapseTerminalAfterFocus()
    }

    @objc func workspaceApplicationDidActivate(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            application.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return }
        collapseTerminalAfterFocus()
    }

    func collapseTerminalAfterFocus() {
        guard terminalPanelMode != .docked else { return }
        returnTerminalToDock()
    }

    func returnTerminalToDock(animated: Bool = true) {
        guard terminalPanelMode != .docked else { return }
        terminalPanelMode = .docked
        expansionScreenID = nil
        terminalPanelController.setResizable(false)
        applyTerminalAppearance()
        refreshCoarseCaches()
        let presence = resolveDockPresence()
        if let target = collapseTarget(for: presence) {
            showTerminal(target, animated: animated)
        } else {
            panel.orderOut(nil)
        }
        if let presence, case .concealed = presence {
            hideReadOnlyDeck()
        } else if let presence, let frame = readOnlyDeckFrame(for: presence) {
            showReadOnlyDeck(frame)
        } else {
            hideReadOnlyDeck()
        }
        debugLog("expand", "returned terminal to Dock")
        updateFallbackHintVisibility()
    }

    func resizeFocusedTerminalIfNeeded() {
        guard isFocusExpanded, !isExpanded else { return }
        refreshCoarseCaches()
        let presence = resolveDockPresence()
        let screen = expansionScreen(fallingBackTo: presence?.host)
        let collapsed = collapsedFrame ?? presence.flatMap { collapsedFrames(for: $0).terminal }
        guard let screen, let collapsed else { return }
        setFocusedTerminalResizable(collapsed: collapsed, hostFrame: screen.frame)
        showTerminal(
            focusedTerminalFrame(collapsed: collapsed, hostFrame: screen.frame), animated: true)
    }

    private func focusedTerminalFrame(collapsed: NSRect, hostFrame: NSRect) -> NSRect {
        DockPanelLayout.focusedTerminalFrame(
            collapsed: collapsed,
            hostFrame: hostFrame,
            widthMultiplier: PanelSettings.focusWidthMultiplier,
            heightMultiplier: PanelSettings.focusHeightMultiplier)
    }

    private func setFocusedTerminalResizable(collapsed: NSRect, hostFrame: NSRect) {
        let minimum = DockPanelLayout.focusedTerminalFrame(
            collapsed: collapsed,
            hostFrame: hostFrame,
            widthMultiplier: DockPanelLayout.minimumFocusedWidthMultiplier,
            heightMultiplier: DockPanelLayout.minimumFocusedHeightMultiplier)
        let maximum = DockPanelLayout.focusedTerminalFrame(
            collapsed: collapsed,
            hostFrame: hostFrame,
            widthMultiplier: DockPanelLayout.maximumFocusedWidthMultiplier,
            heightMultiplier: DockPanelLayout.maximumFocusedHeightMultiplier)
        terminalPanelController.setResizable(
            true, minSize: minimum.size, maxSize: maximum.size)
    }
}
