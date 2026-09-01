import Cocoa

struct DockPanelFrames: Equatable {
    let terminal: NSRect?
    let quota: NSRect?

    func ordered(_ order: PanelOrder) -> DockPanelFrames {
        switch order {
        case .terminalLeft: self
        case .terminalRight: DockPanelFrames(terminal: quota, quota: terminal)
        }
    }
}

enum DockPanelLayout {
    static let gap: CGFloat = 4
    static let minimumPanelWidth: CGFloat = 160
    static let fallbackPanelWidth: CGFloat = 214
    static let fallbackHeight: CGFloat = 64
    static let fallbackBottomInset: CGFloat = 5
    static let fallbackTopInset: CGFloat = 1
    static let focusedWidthMultiplier: CGFloat = 2
    static let focusedHeightMultiplier: CGFloat = 4
    static let minimumFocusedWidthMultiplier: CGFloat = 1.25
    static let maximumFocusedWidthMultiplier: CGFloat = 4
    static let minimumFocusedHeightMultiplier: CGFloat = 2
    static let maximumFocusedHeightMultiplier: CGFloat = 8
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
        let totalInset = fallbackBottomInset + fallbackTopInset
        let dockRegionHeight = reservedHeight > totalInset ? reservedHeight : fallbackHeight
        let height = dockRegionHeight - totalInset
        let minY = hostFrame.minY + fallbackBottomInset
        let terminalWidth = min(fallbackPanelWidth, hostFrame.width)
        let terminal = NSRect(
            x: hostFrame.minX, y: minY, width: terminalWidth, height: height)

        let quota: NSRect?
        if hostFrame.width >= terminalWidth + gap + fallbackPanelWidth {
            quota = NSRect(
                x: hostFrame.maxX - fallbackPanelWidth,
                y: minY,
                width: fallbackPanelWidth,
                height: height)
        } else {
            quota = nil
        }
        return DockPanelFrames(terminal: terminal, quota: quota)
    }

    static func focusedTerminalFrame(
        collapsed: NSRect, hostFrame: NSRect,
        widthMultiplier: CGFloat = focusedWidthMultiplier,
        heightMultiplier: CGFloat = focusedHeightMultiplier
    ) -> NSRect {
        let safeWidthMultiplier = min(
            max(widthMultiplier, minimumFocusedWidthMultiplier), maximumFocusedWidthMultiplier)
        let safeHeightMultiplier = min(
            max(heightMultiplier, minimumFocusedHeightMultiplier), maximumFocusedHeightMultiplier)
        let width = min(collapsed.width * safeWidthMultiplier, hostFrame.width)
        let height = min(collapsed.height * safeHeightMultiplier, hostFrame.height)
        let x = min(max(collapsed.minX, hostFrame.minX), hostFrame.maxX - width)
        let y = min(max(collapsed.minY, hostFrame.minY), hostFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
