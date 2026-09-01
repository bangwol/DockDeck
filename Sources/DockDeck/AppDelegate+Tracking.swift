import ApplicationServices
import Cocoa

extension AppDelegate {
    static let dockTrackingInterval: TimeInterval = 1.0
    static let fastTrackingInterval: TimeInterval = 0.06
    static let coarseTickRatio = 16
    static let armingEdgeStrip: CGFloat = 4

    func tick() {
        tickCount += 1

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
        if panel.isVisible || quotaPanel.isVisible { return true }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            let frame = screen.frame
            return pointer.x >= frame.minX && pointer.x <= frame.maxX
                && pointer.y >= frame.minY && pointer.y <= frame.minY + Self.armingEdgeStrip
        }
    }

    func startTrackingTimer() {
        let interval =
            dockCoordinator.autoHides ? Self.fastTrackingInterval : Self.dockTrackingInterval
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
            hideQuota()
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
            if quotaPanel.isVisible { quotaPanel.orderOut(nil) }
        }
    }

    func showPanels(for presence: DockPresence) {
        let frames = collapsedFrames(for: presence)
        if let terminalFrame = terminalFrame(for: presence) {
            showTerminal(terminalFrame)
        } else if panel.isVisible {
            debugLog("visibility", "hiding terminal; insufficient space beside Dock")
            panel.orderOut(nil)
        }

        if let quotaFrame = frames.quota {
            if !quotaPanel.isVisible { quotaPanel.orderFrontRegardless() }
            applyQuotaFrame(quotaFrame)
        } else {
            hideQuota()
        }
    }

    func showTerminal(_ frame: NSRect, animated: Bool = false) {
        if !panel.isVisible { panel.orderFrontRegardless() }
        applyFrame(frame, animated: animated)
    }

    func hideQuota() {
        guard quotaPanel.isVisible else { return }
        debugLog("visibility", "hiding quota; insufficient space beside Dock")
        quotaPanel.orderOut(nil)
    }

    func restoreLastFullyVisibleFrameIfStranded(on host: NSScreen) {
        guard !isExpanded, panel.frame.minY < host.frame.minY else { return }
        guard let remembered = collapsedFrame,
            NSScreen.screens.contains(where: { $0.frame.contains(remembered) })
        else {
            return
        }
        debugLog("visibility", "pulling a mid-slide panel back to \(remembered)")
        applyFrame(remembered)
    }

    func applyFrame(_ frame: NSRect, animated: Bool = false) {
        if !isExpanded, NSScreen.screens.contains(where: { $0.frame.contains(frame) }) {
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

    func applyQuotaFrame(_ frame: NSRect) {
        guard quotaPanel.frame != frame else { return }
        debugLog("quota-frame", "\(frame)")
        quotaPanel.setFrame(frame, display: true)
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
