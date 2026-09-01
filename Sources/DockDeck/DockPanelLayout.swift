import Cocoa

struct DockPanelFrames: Equatable {
    let terminal: NSRect?
    let quota: NSRect?
}

enum DockPanelLayout {
    static let gap: CGFloat = 4
    static let terminalMinimumWidth: CGFloat = 200
    static let quotaMinimumWidth: CGFloat = 200
    static let fallbackTerminalWidth: CGFloat = 300
    static let fallbackQuotaWidth: CGFloat = 260
    static let fallbackHeight: CGFloat = 64
    static let dockBottomCorrection: CGFloat = 5
    static let dockTopCorrection: CGFloat = 5

    static func frames(tray: NSRect, hostFrame: NSRect) -> DockPanelFrames {
        let minY = tray.minY - dockBottomCorrection
        let maxY = tray.maxY - dockTopCorrection
        guard maxY > minY else { return DockPanelFrames(terminal: nil, quota: nil) }

        let terminalWidth = tray.minX - hostFrame.minX - gap
        let quotaWidth = hostFrame.maxX - tray.maxX - gap
        let height = maxY - minY

        let terminal =
            terminalWidth >= terminalMinimumWidth
            ? NSRect(x: hostFrame.minX, y: minY, width: terminalWidth, height: height)
            : nil
        let quota =
            quotaWidth >= quotaMinimumWidth
            ? NSRect(x: tray.maxX + gap, y: minY, width: quotaWidth, height: height)
            : nil
        return DockPanelFrames(terminal: terminal, quota: quota)
    }

    static func fallbackFrames(hostFrame: NSRect, reservedHeight: CGFloat) -> DockPanelFrames {
        let height = reservedHeight > 4 ? reservedHeight : fallbackHeight
        let terminalWidth = min(fallbackTerminalWidth, hostFrame.width)
        let terminal = NSRect(
            x: hostFrame.minX, y: hostFrame.minY, width: terminalWidth, height: height)

        let quota: NSRect?
        if hostFrame.width >= terminalWidth + gap + fallbackQuotaWidth {
            quota = NSRect(
                x: hostFrame.maxX - fallbackQuotaWidth,
                y: hostFrame.minY,
                width: fallbackQuotaWidth,
                height: height)
        } else {
            quota = nil
        }
        return DockPanelFrames(terminal: terminal, quota: quota)
    }
}
