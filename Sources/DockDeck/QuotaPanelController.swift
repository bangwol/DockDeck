import Cocoa
import SwiftUI

private final class ReadOnlyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class QuotaPanelController {
    let panel: NSPanel

    private let surfaceView: PanelSurfaceView
    private let hostingView: NSHostingView<QuotaPanelView>
    private let store: UsageStore

    init(initialFrame: NSRect, theme: Theme, store: UsageStore) {
        self.store = store

        let panel = ReadOnlyPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = NSWindow.Level(rawValue: Int(kCGDockWindowLevel) + 1)
        panel.title = "DockDeck Usage"
        panel.setAccessibilityLabel("DockDeck Usage")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let surfaceView = PanelSurfaceView(
            frame: NSRect(origin: .zero, size: initialFrame.size), theme: theme)

        let hostingView = NSHostingView(rootView: QuotaPanelView(store: store, theme: theme))
        hostingView.frame = surfaceView.bounds
        hostingView.autoresizingMask = [.width, .height]
        surfaceView.contentContainer.addSubview(hostingView)

        panel.contentView = surfaceView
        self.panel = panel
        self.surfaceView = surfaceView
        self.hostingView = hostingView
    }

    func applyTheme(_ theme: Theme) {
        surfaceView.apply(theme: theme, presentation: .compact)
        hostingView.rootView = QuotaPanelView(store: store, theme: theme)
    }

    func applyCornerRadius() {
        surfaceView.applyCornerRadius()
    }
}
