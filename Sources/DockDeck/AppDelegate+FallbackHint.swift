import Cocoa

extension AppDelegate {
    static let fallbackHintOverlap: CGFloat = 6
    static let fallbackHintWidth: CGFloat = 300
    static let fallbackHintMessage = """
        DockDeck needs Accessibility permission only to read the Dock's position and size.

        System Settings → Privacy & Security → Accessibility → DockDeck.

        If DockDeck is already enabled after a rebuild, turn it off and on once.

        ⌘E expands · ⌘T themes · ⌘Q quits
        """

    func installFallbackHintIfNeeded() {
        guard hintPanel == nil else { return }
        let (hint, tintView, label) = FallbackHintPanel.make(
            message: Self.fallbackHintMessage, width: Self.fallbackHintWidth, theme: currentTheme,
            cornerRadius: PanelSettings.cornerRadius, tintOpacity: PanelSettings.tintOpacity,
            font: TerminalTheme.font(named: PanelSettings.fontName),
            target: self, action: #selector(dismissFallbackHint))
        hintPanel = hint
        hintTintView = tintView
        hintLabel = label
    }

    func applyThemeToFallbackHint(_ theme: Theme) {
        hintTintView?.layer?.backgroundColor = theme.tintColor(opacity: PanelSettings.tintOpacity).cgColor
        hintLabel?.textColor = theme.foregroundColor
    }

    @objc func dismissFallbackHint() {
        hintDismissed = true
        guard let hint = hintPanel else { return }
        panel.removeChildWindow(hint)
        hint.orderOut(nil)
    }

    func updateFallbackHintVisibility() {
        guard !accessibilityTrusted, !hintDismissed, let hint = hintPanel else {
            hintPanel?.orderOut(nil)
            return
        }
        guard panel.isVisible, lastPresenceUntracked, !isExpanded, !isFocusExpanded else {
            hint.orderOut(nil)
            return
        }
        positionFallbackHint()
        if hint.parent !== panel {
            panel.addChildWindow(hint, ordered: .below)
        }
        hint.orderFront(nil)
    }

    func positionFallbackHint() {
        guard let hint = hintPanel else { return }
        let mainFrame = panel.frame
        hint.setFrameOrigin(
            NSPoint(x: mainFrame.minX, y: mainFrame.maxY - Self.fallbackHintOverlap))
    }
}
