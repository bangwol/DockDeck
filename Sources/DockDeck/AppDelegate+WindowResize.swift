import Cocoa

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        settingsPanelDidClose(window)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        terminalView.frame = TerminalLayout.contentFrame(
            in: NSRect(origin: .zero, size: window.frame.size), font: terminalView.font)
        positionFallbackHint()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel,
            animatingTerminalFrame == nil
        else { return }
        terminalResizeDidEnd()
    }

    func terminalResizeDidEnd() {
        guard isFocusExpanded, !isExpanded, let collapsedFrame,
            collapsedFrame.width > 0, collapsedFrame.height > 0
        else { return }

        PanelSettings.focusWidthMultiplier = panel.frame.width / collapsedFrame.width
        PanelSettings.focusHeightMultiplier = panel.frame.height / collapsedFrame.height
        debugLog(
            "resize",
            "saved focus size \(PanelSettings.focusWidthMultiplier)x"
                + " by \(PanelSettings.focusHeightMultiplier)x")
    }
}
