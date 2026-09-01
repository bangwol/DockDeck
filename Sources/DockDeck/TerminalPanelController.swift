import Cocoa
import SwiftTerm

final class TerminalPanelController {
    let panel: KeyablePanel
    let terminalView: LocalProcessTerminalView
    let surfaceView: PanelSurfaceView
    let menuButton: NSButton

    init(
        initialFrame: NSRect, theme: Theme, menuTarget: AnyObject, menuAction: Selector
    ) {
        let built = PanelBuilder.makePanel(
            initialFrame: initialFrame,
            theme: theme,
            menuTarget: menuTarget,
            menuAction: menuAction)
        panel = built.panel
        terminalView = built.terminal
        surfaceView = built.surfaceView
        menuButton = built.menuButton
    }

    func applyAppearance(_ theme: Theme, presentation: PanelPresentation) {
        surfaceView.apply(theme: theme, presentation: presentation)
    }

    func applyCornerRadius() {
        surfaceView.applyCornerRadius()
    }

    func setResizable(_ enabled: Bool, minSize: NSSize = .zero, maxSize: NSSize = .zero) {
        if enabled {
            panel.minSize = minSize
            panel.maxSize = maxSize
            panel.styleMask.insert(.resizable)
        } else {
            panel.styleMask.remove(.resizable)
        }
    }

    func startShell() {
        terminalView.startProcess(
            executable: ShellEnvironment.executable,
            args: ["-l"],
            environment: ShellEnvironment.variables(),
            currentDirectory: NSHomeDirectory()
        )
    }
}
