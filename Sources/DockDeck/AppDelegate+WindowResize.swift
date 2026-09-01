import Cocoa

extension AppDelegate: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        terminalView.frame = TerminalLayout.contentFrame(
            in: NSRect(origin: .zero, size: window.frame.size), font: terminalView.font)
        positionFallbackHint()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel,
            isFocusExpanded, !isExpanded, let collapsedFrame,
            collapsedFrame.width > 0, collapsedFrame.height > 0
        else {
            return
        }

        PanelSettings.focusWidthMultiplier = window.frame.width / collapsedFrame.width
        PanelSettings.focusHeightMultiplier = window.frame.height / collapsedFrame.height
        debugLog(
            "resize",
            "saved focus size \(PanelSettings.focusWidthMultiplier)x"
                + " by \(PanelSettings.focusHeightMultiplier)x")
    }
}
