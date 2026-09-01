import ApplicationServices
import Cocoa

extension AppDelegate {
    static let dockTrackingInterval: TimeInterval = 3.0
    static let fastTrackingInterval: TimeInterval = 0.10
    static let untrustedTrackingInterval: TimeInterval = 5.0
    static let coarseTickRatio = 30
    static let armingEdgeStrip: CGFloat = 4

    func tick() {
        tickCount += 1

        if !accessibilityTrusted {
            refreshCoarseCaches()
            startTrackingTimer()
            runEvaluation()
            return
        }

        if !dockCoordinator.autoHides || tickCount % Self.coarseTickRatio == 0 {
            refreshCoarseCaches()
            startTrackingTimer()
            runEvaluation()
            return
        }

        guard dockCoordinator.autoHides, !lastPresenceUntracked else { return }
        guard !isHeld else { return }
        guard isArmed() else { return }

        runEvaluation()
    }

    func isArmed() -> Bool {
        if panel.isVisible || readOnlyDeckPanel.isVisible { return true }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            let frame = screen.frame
            return pointer.x >= frame.minX && pointer.x <= frame.maxX
                && pointer.y >= frame.minY && pointer.y <= frame.minY + Self.armingEdgeStrip
        }
    }

    func startTrackingTimer() {
        let interval: TimeInterval
        if !accessibilityTrusted {
            interval = Self.untrustedTrackingInterval
        } else {
            interval =
                dockCoordinator.autoHides ? Self.fastTrackingInterval : Self.dockTrackingInterval
        }
        guard trackingTimer == nil || trackingTimer.timeInterval != interval else { return }

        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
        debugLog("timer", "tracking at \(interval)s")
    }

    func refreshCoarseCaches() {
        let nowTrusted = dockCoordinator.isAccessibilityTrusted
        if nowTrusted != accessibilityTrusted {
            accessibilityTrusted = nowTrusted
            if !nowTrusted {
                hintDismissed = false
                installFallbackHintIfNeeded()
            }
        }

        dockCoordinator.refresh()
    }

    var isHeld: Bool { (panel.isKeyWindow || isExpanded) && isFrozen }

    func runEvaluation() {
        defer { updateFallbackHintVisibility() }
        guard let presence = resolveDockPresence() else {
            debugLog("screens", "no screen at all; falling back\(isHeld ? " (held)" : "")")
            lastPresenceUntracked = true
            guard !isHeld else { return }
            showTerminal(
                NSRect(x: 0, y: 0, width: Self.fallbackWidth, height: Self.fallbackHeight))
            hideReadOnlyDeck()
            return
        }
        evaluate(presence)
    }

    func evaluate(_ presence: DockPresence) {
        defer { updateFallbackHintVisibility() }
        let exempt = panel.isKeyWindow || isExpanded
        lastPresenceUntracked = presence.isUntracked

        debugLog(
            "state",
            "\(presence.summary) orientation=\(dockCoordinator.orientation) "
                + "autohide=\(dockCoordinator.autoHides) exempt=\(exempt) frozen=\(isFrozen) "
                + "expansion=\(describe(expansionScreenID))")

        switch presence {
        case .revealed(let tray, let host):
            let midSlide = tray.minY < host.frame.minY
            let concealing = midSlide && !wasConcealed
            wasConcealed = false

            if exempt, concealing {
                isFrozen = true
                restoreLastFullyVisibleFrameIfStranded(on: host)
                return
            }
            if exempt, midSlide {
                return
            }
            if exempt, isFrozen, panel.screen !== host {
                return
            }
            isFrozen = false
            showPanels(for: presence)
        case .untracked(let host):
            wasConcealed = false
            if exempt, isFrozen, panel.screen !== host {
                return
            }
            isFrozen = false
            showPanels(for: presence)
        case .concealed:
            wasConcealed = true
            if exempt {
                isFrozen = true
                return
            }
            isFrozen = false
            if panel.isVisible {
                debugLog("visibility", "concealing with the Dock")
                panel.orderOut(nil)
            }
            if readOnlyDeckPanel.isVisible { readOnlyDeckPanel.orderOut(nil) }
        }
    }

    func showPanels(for presence: DockPresence) {
        let frames = collapsedFrames(for: presence)
        let enabledPanels = PanelSettings.enabledPanels
        if enabledPanels.contains(.terminal), let terminalFrame = terminalFrame(for: presence) {
            showTerminal(terminalFrame)
        } else if panel.isVisible {
            let reason = enabledPanels.contains(.terminal)
                ? "insufficient space beside Dock" : "disabled in settings"
            debugLog("visibility", "hiding terminal; \(reason)")
            panel.orderOut(nil)
        }

        if !PanelSettings.enabledReadOnlyModules.isEmpty, let readOnlyFrame = frames.quota {
            showReadOnlyDeck(readOnlyFrame)
        } else {
            let reason = !PanelSettings.enabledReadOnlyModules.isEmpty
                ? "insufficient space beside Dock" : "disabled in settings"
            hideReadOnlyDeck(reason: reason)
        }
    }

    func showTerminal(_ frame: NSRect, animated: Bool = false) {
        guard PanelSettings.enabledPanels.contains(.terminal) else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        applyFrame(frame, animated: animated)
    }

    func showReadOnlyDeck(_ frame: NSRect) {
        guard !PanelSettings.enabledReadOnlyModules.isEmpty else {
            hideReadOnlyDeck(reason: "disabled in settings")
            return
        }
        if !readOnlyDeckPanel.isVisible { readOnlyDeckPanel.orderFrontRegardless() }
        applyReadOnlyDeckFrame(frame)
    }

    func hideReadOnlyDeck(reason: String = "insufficient space beside Dock") {
        guard readOnlyDeckPanel.isVisible else { return }
        debugLog("visibility", "hiding read-only deck; \(reason)")
        readOnlyDeckPanel.orderOut(nil)
    }

    func restoreLastFullyVisibleFrameIfStranded(on host: NSScreen) {
        guard !isExpanded, !isFocusExpanded, panel.frame.minY < host.frame.minY else { return }
        guard let remembered = collapsedFrame,
            NSScreen.screens.contains(where: { $0.frame.contains(remembered) })
        else {
            return
        }
        debugLog("visibility", "pulling a mid-slide panel back to \(remembered)")
        applyFrame(remembered)
    }

    func applyFrame(_ frame: NSRect, animated: Bool = false) {
        if !isExpanded, !isFocusExpanded,
            NSScreen.screens.contains(where: { $0.frame.contains(frame) })
        {
            collapsedFrame = frame
        }
        guard panel.frame != frame else { return }
        debugLog("frame", "\(frame)")

        let layoutTerminal = {
            self.terminalView.frame = TerminalLayout.contentFrame(
                in: NSRect(origin: .zero, size: frame.size), font: self.terminalView.font)
            self.positionFallbackHint()
        }

        guard animated else {
            panel.setFrame(frame, display: true)
            layoutTerminal()
            return
        }

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }, completionHandler: layoutTerminal)
    }

    func applyReadOnlyDeckFrame(_ frame: NSRect) {
        guard readOnlyDeckPanel.frame != frame else { return }
        debugLog("read-only-frame", "\(frame)")
        readOnlyDeckPanel.setFrame(frame, display: true)
    }

    func collapseTarget(for presence: DockPresence?) -> NSRect? {
        var held = isFrozen
        if case .concealed? = presence { held = true }

        if held, let remembered = collapsedFrame,
            NSScreen.screens.contains(where: { $0.frame.intersects(remembered) })
        {
            return remembered
        }
        guard let presence else {
            return NSRect(x: 0, y: 0, width: Self.fallbackWidth, height: Self.fallbackHeight)
        }
        return collapsedFrames(for: presence).terminal
    }

    func expansionScreen(fallingBackTo host: NSScreen?) -> NSScreen? {
        panel.screen ?? screenWithGreatestIntersection(with: panel.frame) ?? host
            ?? mainDisplayScreen()
    }

    @objc func screenParametersChanged(_ notification: Notification) {
        defer { updateFallbackHintVisibility() }
        isFrozen = false
        refreshCoarseCaches()
        let presence = resolveDockPresence()
        debugLog("screens", "configuration changed; panel at \(panel.frame)")
        guard let presence else { return }
        if isExpanded,
            !NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) })
        {
            expansionScreenID = displayID(of: presence.host)
        }
        evaluate(presence)
    }
}
