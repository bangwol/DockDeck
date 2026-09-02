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
        if panel.isVisible || readOnlyDeckPanels.contains(where: \.isVisible) { return true }
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
        // Coarse polling can drift; the 0.1 s auto-hide tracker stays exact for responsiveness.
        timer.tolerance = interval >= 1 ? interval * 0.1 : 0
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
            let left = NSRect(
                x: 0, y: 0, width: Self.fallbackWidth, height: Self.fallbackHeight)
            let right = NSRect(
                x: left.maxX + DockPanelLayout.gap, y: 0,
                width: Self.fallbackWidth, height: Self.fallbackHeight)
            showPanels(in: DockPanelFrames(terminal: left, quota: right))
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
            hideReadOnlyDecks()
        }
    }

    func showPanels(for presence: DockPresence) {
        let frames = collapsedFrames(for: presence)
        showPanels(in: frames, terminalTarget: terminalFrame(for: presence))
    }

    func showPanels(
        in frames: DockPanelFrames, terminalTarget: NSRect? = nil,
        terminalAnimated: Bool = false
    ) {
        let configuration = PanelSettings.deckConfiguration
        let terminalSide = configuration.side(containing: .terminal) ?? .left
        let terminalActive = configuration.contains(.terminal)
            && PanelSettings.activeModule(on: terminalSide) == .terminal
        let terminalFrame = terminalTarget ?? frames.frame(on: terminalSide)
        if terminalActive, let terminalFrame {
            showTerminal(terminalFrame, animated: terminalAnimated)
        } else {
            if panel.isVisible {
                let reason = terminalActive
                    ? "insufficient space beside Dock" : "another deck module is active"
                debugLog("visibility", "hiding terminal; \(reason)")
                panel.orderOut(nil)
            }
        }

        for side in PanelSide.allCases {
            let activeModule = PanelSettings.activeModule(on: side)
            if let activeModule, activeModule != .terminal, let frame = frames.frame(on: side) {
                showReadOnlyDeck(on: side, frame: frame)
            } else {
                let reason = activeModule == nil
                    ? "no enabled module in deck"
                    : activeModule == .terminal
                        ? "terminal is active" : "insufficient space beside Dock"
                hideReadOnlyDeck(on: side, reason: reason)
            }
        }
    }

    func showTerminal(_ frame: NSRect, animated: Bool = false) {
        let configuration = PanelSettings.deckConfiguration
        guard configuration.contains(.terminal),
            let side = configuration.side(containing: .terminal),
            PanelSettings.activeModule(on: side) == .terminal
        else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        applyFrame(frame, animated: animated)
    }

    func showReadOnlyDeck(on side: PanelSide, frame: NSRect) {
        let controller = readOnlyDeckPanelController(on: side)
        guard let activeModule = PanelSettings.activeModule(on: side),
            activeModule != .terminal
        else {
            hideReadOnlyDeck(on: side, reason: "no read-only module is active")
            return
        }
        controller.synchronizeActiveModule()
        if !controller.panel.isVisible { controller.panel.orderFrontRegardless() }
        applyReadOnlyDeckFrame(frame, on: side)
    }

    func hideReadOnlyDeck(
        on side: PanelSide, reason: String = "insufficient space beside Dock"
    ) {
        let panel = readOnlyDeckPanelController(on: side).panel
        guard panel.isVisible else { return }
        debugLog("visibility", "hiding \(side.rawValue) deck; \(reason)")
        panel.orderOut(nil)
    }

    func hideReadOnlyDecks(reason: String = "insufficient space beside Dock") {
        for side in PanelSide.allCases { hideReadOnlyDeck(on: side, reason: reason) }
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
        guard panel.frame != frame, animatingTerminalFrame != frame else { return }
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

        animatingTerminalFrame = frame
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            },
            completionHandler: { [weak self] in
                guard let self else { return }
                if self.animatingTerminalFrame == frame { self.animatingTerminalFrame = nil }
                layoutTerminal()
            })
    }

    func applyReadOnlyDeckFrame(_ frame: NSRect, on side: PanelSide) {
        let panel = readOnlyDeckPanelController(on: side).panel
        guard panel.frame != frame else { return }
        debugLog("\(side.rawValue)-deck-frame", "\(frame)")
        panel.setFrame(frame, display: true)
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
        let side = PanelSettings.deckConfiguration.side(containing: .terminal) ?? .left
        return collapsedFrames(for: presence).frame(on: side)
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
