import Cocoa
import CoreGraphics
import SwiftTerm

enum PanelBuilder {
    static let menuButtonSize: CGFloat = 15
    static let menuButtonInset: CGFloat = 5

    static func makePanel(
        initialFrame: NSRect, theme: Theme, menuTarget: AnyObject, menuAction: Selector
    ) -> (
        panel: KeyablePanel, terminal: LocalProcessTerminalView, surfaceView: PanelSurfaceView,
        menuButton: NSButton
    ) {
        let panel = KeyablePanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(kCGDockWindowLevel) + 1)
        panel.title = "DockDeck Terminal"
        panel.setAccessibilityLabel("DockDeck Terminal")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.hidesOnDeactivate = false

        let surfaceView = PanelSurfaceView(
            frame: NSRect(origin: .zero, size: panel.frame.size), theme: theme)

        let font = TerminalTheme.font(named: PanelSettings.fontName)
        let terminal = LocalProcessTerminalView(
            frame: TerminalLayout.contentFrame(in: surfaceView.bounds, font: font))
        terminal.autoresizingMask = [.width]
        terminal.font = font
        terminal.nativeBackgroundColor = .clear
        terminal.nativeForegroundColor = theme.foregroundColor
        terminal.layer?.backgroundColor = NSColor.clear.cgColor
        terminal.installColors(theme.ansiPalette)
        terminal.toolTip = "Click to expand · drag edges to resize · ⌘E full size · ⌘T theme"

        surfaceView.contentContainer.addSubview(terminal)

        let menuButton = NSButton(
            image: NSImage(
                systemSymbolName: "ellipsis.circle", accessibilityDescription: "Menu")!,
            target: menuTarget, action: menuAction)
        menuButton.frame = NSRect(
            x: surfaceView.bounds.width - menuButtonSize - menuButtonInset,
            y: surfaceView.bounds.height - menuButtonSize - menuButtonInset,
            width: menuButtonSize, height: menuButtonSize)
        menuButton.autoresizingMask = [.minXMargin, .minYMargin]
        menuButton.isBordered = false
        menuButton.imagePosition = .imageOnly
        menuButton.contentTintColor = theme.chromeTintColor
        (menuButton.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown
        menuButton.toolTip = "Menu"
        surfaceView.contentContainer.addSubview(menuButton)

        panel.contentView = surfaceView

        return (panel, terminal, surfaceView, menuButton)
    }
}
