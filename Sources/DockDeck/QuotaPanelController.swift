import Cocoa
import SwiftUI

private final class ReadOnlyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class QuotaPanelController {
    let panel: NSPanel
    let tintView: NSView

    private let effectView: NSVisualEffectView
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

        let effectView = NSVisualEffectView(
            frame: NSRect(origin: .zero, size: initialFrame.size))
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = PanelSettings.cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        let tintView = NSView(frame: effectView.bounds)
        tintView.autoresizingMask = [.width, .height]
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor =
            theme.tintColor(opacity: PanelSettings.tintOpacity).cgColor
        effectView.addSubview(tintView)

        let hostingView = NSHostingView(rootView: QuotaPanelView(store: store, theme: theme))
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)

        panel.contentView = effectView
        self.panel = panel
        self.effectView = effectView
        self.tintView = tintView
        self.hostingView = hostingView
    }

    func applyTheme(_ theme: Theme) {
        tintView.layer?.backgroundColor =
            theme.tintColor(opacity: PanelSettings.tintOpacity).cgColor
        hostingView.rootView = QuotaPanelView(store: store, theme: theme)
    }

    func applyCornerRadius() {
        effectView.layer?.cornerRadius = PanelSettings.cornerRadius
    }
}
