import Cocoa

struct DockPanelFrames: Equatable {
    let terminal: NSRect?
    let quota: NSRect?
}

enum DockPanelLayout {
    static let gap: CGFloat = 4
    static let minimumPanelWidth: CGFloat = 160
    static let fallbackPanelWidth: CGFloat = 214
    static let fallbackHeight: CGFloat = 64
    static let focusedWidthMultiplier: CGFloat = 2
    static let focusedHeightMultiplier: CGFloat = 4
    static let dockBottomCorrection: CGFloat = 5
    static let dockTopCorrection: CGFloat = 5

    static func frames(tray: NSRect, hostFrame: NSRect) -> DockPanelFrames {
        let minY = tray.minY - dockBottomCorrection
        let maxY = tray.maxY - dockTopCorrection
        guard maxY > minY else { return DockPanelFrames(terminal: nil, quota: nil) }

        let terminalAvailableWidth = tray.minX - hostFrame.minX - gap
        let quotaAvailableWidth = hostFrame.maxX - tray.maxX - gap
        let panelWidth = min(terminalAvailableWidth, quotaAvailableWidth)
        let height = maxY - minY

        guard panelWidth >= minimumPanelWidth else {
            return DockPanelFrames(terminal: nil, quota: nil)
        }
        return DockPanelFrames(
            terminal: NSRect(
                x: hostFrame.minX, y: minY, width: panelWidth, height: height),
            quota: NSRect(
                x: hostFrame.maxX - panelWidth, y: minY,
                width: panelWidth, height: height))
    }

    static func fallbackFrames(hostFrame: NSRect, reservedHeight: CGFloat) -> DockPanelFrames {
        let height = reservedHeight > 4 ? reservedHeight : fallbackHeight
        let terminalWidth = min(fallbackPanelWidth, hostFrame.width)
        let terminal = NSRect(
            x: hostFrame.minX, y: hostFrame.minY, width: terminalWidth, height: height)

        let quota: NSRect?
        if hostFrame.width >= terminalWidth + gap + fallbackPanelWidth {
            quota = NSRect(
                x: hostFrame.maxX - fallbackPanelWidth,
                y: hostFrame.minY,
                width: fallbackPanelWidth,
                height: height)
        } else {
            quota = nil
        }
        return DockPanelFrames(terminal: terminal, quota: quota)
    }

    static func focusedTerminalFrame(collapsed: NSRect, hostFrame: NSRect) -> NSRect {
        let width = min(collapsed.width * focusedWidthMultiplier, hostFrame.width)
        let height = min(collapsed.height * focusedHeightMultiplier, hostFrame.height)
        let x = min(max(collapsed.minX, hostFrame.minX), hostFrame.maxX - width)
        let y = min(max(collapsed.minY, hostFrame.minY), hostFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
