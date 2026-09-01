import Cocoa
import SwiftTerm

final class TerminalPanelController {
    let panel: KeyablePanel
    let terminalView: LocalProcessTerminalView
    let tintView: NSView
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
        tintView = built.tintView
        menuButton = built.menuButton
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
