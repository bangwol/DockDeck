import Cocoa
import SwiftTerm

struct ShellRestartPolicy {
    static let rapidExitThreshold: TimeInterval = 2
    static let maximumRapidRestarts = 2

    private(set) var startedAt: Date?
    private(set) var rapidExitCount = 0

    mutating func recordStart(at date: Date) {
        startedAt = date
    }

    mutating func shouldRestart(afterExitAt date: Date) -> Bool {
        guard let startedAt else { return false }
        if date.timeIntervalSince(startedAt) < Self.rapidExitThreshold {
            rapidExitCount += 1
        } else {
            rapidExitCount = 0
        }
        self.startedAt = nil
        return rapidExitCount <= Self.maximumRapidRestarts
    }

    mutating func reset() {
        startedAt = nil
        rapidExitCount = 0
    }
}

final class TerminalPanelController: NSObject, LocalProcessTerminalViewDelegate {
    let panel: KeyablePanel
    let terminalView: LocalProcessTerminalView
    let surfaceView: PanelSurfaceView
    let menuButton: NSButton

    private let onShellEvent: (String) -> Void
    private var restartPolicy = ShellRestartPolicy()
    private var scheduledRestart: DispatchWorkItem?
    private var automaticallyRestartsShell = true

    init(
        initialFrame: NSRect, theme: Theme, menuTarget: AnyObject, menuAction: Selector,
        onShellEvent: @escaping (String) -> Void = { _ in }
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
        self.onShellEvent = onShellEvent
        super.init()
        terminalView.processDelegate = self
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
        automaticallyRestartsShell = true
        scheduledRestart?.cancel()
        restartPolicy.reset()
        startShellSession()
    }

    func ensureShellRunning() {
        guard !terminalView.process.running else { return }
        scheduledRestart?.cancel()
        restartPolicy.reset()
        startShellSession()
    }

    func stopShell() {
        automaticallyRestartsShell = false
        scheduledRestart?.cancel()
        if terminalView.process.running {
            terminalView.terminate()
        }
    }

    private func startShellSession() {
        guard automaticallyRestartsShell, !terminalView.process.running else { return }
        scheduledRestart = nil
        terminalView.terminal.resetToInitialState()
        restartPolicy.recordStart(at: Date())
        terminalView.startProcess(
            executable: ShellEnvironment.executable,
            args: ["-l"],
            environment: ShellEnvironment.variables(),
            currentDirectory: NSHomeDirectory()
        )
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            self?.handleShellTermination(exitCode: exitCode)
        }
    }

    private func handleShellTermination(exitCode: Int32?) {
        guard automaticallyRestartsShell else { return }
        onShellEvent("shell exited with status \(exitCode.map(String.init) ?? "unknown")")
        guard restartPolicy.shouldRestart(afterExitAt: Date()) else {
            terminalView.feed(
                text: "\r\nDockDeck shell stopped. Click the terminal to start a new session.\r\n")
            return
        }

        let restart = DispatchWorkItem { [weak self] in
            self?.startShellSession()
        }
        scheduledRestart = restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: restart)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
