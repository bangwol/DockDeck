import Cocoa

enum DockPanelMode: CaseIterable {
    case full
    case capsule
    case tab

    var minimumWidth: CGFloat {
        switch self {
        case .full: 160
        case .capsule: 84
        case .tab: 28
        }
    }

    static func resolved(availableWidth: CGFloat, previous: Self? = nil) -> Self {
        // Shrink immediately; require a little spare room before growing again.
        let fullThreshold = Self.full.minimumWidth + (previous != nil && previous != .full ? 12 : 0)
        let capsuleThreshold = Self.capsule.minimumWidth + (previous == .tab ? 12 : 0)
        if availableWidth >= fullThreshold { return .full }
        if availableWidth >= capsuleThreshold { return .capsule }
        return .tab
    }
}

struct DockPanelFrames: Equatable {
    let terminal: NSRect?
    let quota: NSRect?
    var leftMode: DockPanelMode = .full
    var rightMode: DockPanelMode = .full

    func frame(on side: PanelSide) -> NSRect? {
        side == .left ? terminal : quota
    }

    func mode(on side: PanelSide) -> DockPanelMode {
        side == .left ? leftMode : rightMode
    }

    func ordered(_ order: PanelOrder) -> DockPanelFrames {
        switch order {
        case .terminalLeft: self
        case .terminalRight:
            DockPanelFrames(terminal: quota, quota: terminal, leftMode: rightMode, rightMode: leftMode)
        }
    }
}

enum DockPanelLayout {
    static let gap: CGFloat = 4
    static let minimumPanelWidth = DockPanelMode.full.minimumWidth
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

    static func frames(
        tray: NSRect, hostFrame: NSRect, previous: DockPanelFrames? = nil
    ) -> DockPanelFrames {
        let minY = tray.minY - dockBottomCorrection
        let maxY = tray.maxY - dockTopCorrection
        guard [tray.minX, tray.maxX, minY, maxY, hostFrame.minX, hostFrame.maxX,
               hostFrame.minY, hostFrame.maxY].allSatisfy(\.isFinite),
            tray.width > 0, tray.height > 0, maxY > minY,
            hostFrame.width > 0, hostFrame.height > 0
        else { return DockPanelFrames(terminal: nil, quota: nil) }

        let terminalAvailableWidth = tray.minX - hostFrame.minX - gap
        let quotaAvailableWidth = hostFrame.maxX - tray.maxX - gap
        let height = maxY - minY
        let leftMode = DockPanelMode.resolved(
            availableWidth: terminalAvailableWidth, previous: previous?.leftMode)
        let rightMode = DockPanelMode.resolved(
            availableWidth: quotaAvailableWidth, previous: previous?.rightMode)

        func frame(on side: PanelSide, availableWidth: CGFloat, mode: DockPanelMode) -> NSRect? {
            let width = mode == .full ? min(availableWidth, hostFrame.width) : mode.minimumWidth
            let panelHeight = mode == .full ? height : min(height, mode == .capsule ? 36 : 48)
            var y = minY
            if availableWidth < width {
                // Keep an accessible tab above the Dock when even 28 pt cannot fit beside it.
                y = tray.maxY + gap
                guard width <= hostFrame.width, y + panelHeight <= hostFrame.maxY else { return nil }
            }
            return NSRect(
                x: side == .left ? hostFrame.minX : hostFrame.maxX - width,
                y: y, width: width, height: panelHeight)
        }
        return DockPanelFrames(
            terminal: frame(on: .left, availableWidth: terminalAvailableWidth, mode: leftMode),
            quota: frame(on: .right, availableWidth: quotaAvailableWidth, mode: rightMode),
            leftMode: leftMode, rightMode: rightMode)
    }

    static func terminalAnchor(
        on side: PanelSide, hostFrame: NSRect, bottom: CGFloat, previousSize: NSSize?
    ) -> NSRect {
        let size = previousSize ?? NSSize(width: fallbackPanelWidth, height: fallbackHeight)
        let width = min(max(size.width, minimumPanelWidth), hostFrame.width)
        let height = min(max(size.height, 1), hostFrame.height)
        return NSRect(
            x: side == .left ? hostFrame.minX : hostFrame.maxX - width,
            y: min(max(bottom, hostFrame.minY), hostFrame.maxY - height),
            width: width, height: height)
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
