import Cocoa

extension AppDelegate {
    static let fallbackWidth = DockPanelLayout.fallbackTerminalWidth
    static let fallbackHeight = DockPanelLayout.fallbackHeight
    static let expandedSizeFraction: CGFloat = 0.75

    func resolveDockPresence() -> DockPresence? {
        dockCoordinator.resolvePresence()
    }

    func terminalFrame(for presence: DockPresence) -> NSRect? {
        if isExpanded {
            let screen = expansionScreenID.flatMap(screen(for:)) ?? presence.host
            return expandedFrame(on: screen)
        }
        return collapsedFrames(for: presence).terminal
    }

    func collapsedFrames(for presence: DockPresence) -> DockPanelFrames {
        dockCoordinator.frames(for: presence)
    }

    func quotaFrame(for presence: DockPresence) -> NSRect? {
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
        dockCoordinator.fallbackFrames(on: screen).terminal
            ?? NSRect(
                x: screen.frame.minX, y: screen.frame.minY,
                width: Self.fallbackWidth, height: Self.fallbackHeight)
    }
}
