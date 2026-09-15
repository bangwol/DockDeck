import Cocoa
import Darwin
import SwiftTerm

struct WindowResizeEdges: OptionSet {
    let rawValue: Int

    static let left = WindowResizeEdges(rawValue: 1 << 0)
    static let right = WindowResizeEdges(rawValue: 1 << 1)
    static let bottom = WindowResizeEdges(rawValue: 1 << 2)
    static let top = WindowResizeEdges(rawValue: 1 << 3)
}

enum WindowResizeGeometry {
    static let hitWidth: CGFloat = 8

    static func edges(
        at point: NSPoint, in bounds: NSRect, hitWidth: CGFloat = hitWidth
    ) -> WindowResizeEdges {
        var edges: WindowResizeEdges = []
        if point.x <= bounds.minX + hitWidth { edges.insert(.left) }
        if point.x >= bounds.maxX - hitWidth { edges.insert(.right) }
        if point.y <= bounds.minY + hitWidth { edges.insert(.bottom) }
        if point.y >= bounds.maxY - hitWidth { edges.insert(.top) }
        return edges
    }

    static func frame(
        from startFrame: NSRect, mouseDelta: NSPoint, edges: WindowResizeEdges,
        minSize: NSSize, maxSize: NSSize
    ) -> NSRect {
        let minimumWidth = max(minSize.width, 1)
        let minimumHeight = max(minSize.height, 1)
        let maximumWidth =
            maxSize.width > 0 ? max(maxSize.width, minimumWidth) : .greatestFiniteMagnitude
        let maximumHeight =
            maxSize.height > 0 ? max(maxSize.height, minimumHeight) : .greatestFiniteMagnitude

        let requestedWidth = startFrame.width
            + (edges.contains(.right) ? mouseDelta.x : 0)
            - (edges.contains(.left) ? mouseDelta.x : 0)
        let requestedHeight = startFrame.height
            + (edges.contains(.top) ? mouseDelta.y : 0)
            - (edges.contains(.bottom) ? mouseDelta.y : 0)
        let width = min(max(requestedWidth, minimumWidth), maximumWidth)
        let height = min(max(requestedHeight, minimumHeight), maximumHeight)

        return NSRect(
            x: edges.contains(.left) ? startFrame.maxX - width : startFrame.minX,
            y: edges.contains(.bottom) ? startFrame.maxY - height : startFrame.minY,
            width: width,
            height: height)
    }
}

private final class TerminalResizeHandleView: NSView {
    weak var excludedView: NSView?
    var onResizeEnd: () -> Void = {}
    private(set) var isResizing = false
    var isEnabled = false {
        didSet {
            isHidden = !isEnabled
            if let window { window.invalidateCursorRects(for: self) }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, !isExcluded(point) else { return nil }
        return WindowResizeGeometry.edges(at: point, in: bounds).isEmpty ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEnabled else { return }
        let width = WindowResizeGeometry.hitWidth
        addCursorRect(
            NSRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height),
            cursor: .resizeLeftRight)
        addCursorRect(
            NSRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height),
            cursor: .resizeLeftRight)
        addCursorRect(
            NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: width),
            cursor: .resizeUpDown)
        addCursorRect(
            NSRect(x: bounds.minX, y: bounds.maxY - width, width: bounds.width, height: width),
            cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let edges = WindowResizeGeometry.edges(
            at: convert(event.locationInWindow, from: nil), in: bounds)
        guard !edges.isEmpty else { return }

        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        isResizing = true
        defer {
            isResizing = false
            onResizeEnd()
        }

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            guard next.type != .leftMouseUp else { break }
            let mouse = NSEvent.mouseLocation
            let frame = WindowResizeGeometry.frame(
                from: startFrame,
                mouseDelta: NSPoint(x: mouse.x - startMouse.x, y: mouse.y - startMouse.y),
                edges: edges,
                minSize: window.minSize,
                maxSize: window.maxSize)
            window.setFrame(frame, display: true)
        }
    }

    private func isExcluded(_ point: NSPoint) -> Bool {
        guard let excludedView, excludedView.window === window else { return false }
        return convert(excludedView.bounds, from: excludedView).contains(point)
    }
}

struct ShellRestartPolicy {
    static let rapidExitThreshold: TimeInterval = 2
    static let maximumRapidRestarts = 2

    private(set) var startedAt: TimeInterval?
    private(set) var rapidExitCount = 0

    mutating func recordStart(at uptime: TimeInterval) {
        startedAt = uptime
    }

    mutating func shouldRestart(afterExitAt uptime: TimeInterval) -> Bool {
        guard let startedAt else { return false }
        if uptime - startedAt < Self.rapidExitThreshold {
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

struct TerminalShellSession {
    private struct Identity: Hashable {
        let pid: pid_t
        let seconds: UInt64
        let microseconds: UInt64

        init(_ info: proc_bsdinfo) {
            pid = pid_t(info.pbi_pid)
            seconds = info.pbi_start_tvsec
            microseconds = info.pbi_start_tvusec
        }
    }

    private let shell: Identity

    init?(pid: pid_t) {
        guard pid > 1, pid != getpid(), let info = Self.info(pid),
            info.pbi_ppid == getpid() else { return nil }
        shell = Identity(info)
    }

    private static func info(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private var members: [Identity] {
        // A terminal's job-control groups share its session. Detached daemons do not.
        if let current = Self.info(shell.pid), Identity(current) != shell { return [] }
        let capacity = max(Int(proc_listallpids(nil, 0)) + 32, 32)
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        return pids.prefix(max(0, min(Int(count), capacity))).compactMap { pid in
            guard pid > 1, pid != getpid(), pid == shell.pid || getsid(pid) == shell.pid,
                let info = Self.info(pid), info.pbi_status != SZOMB else { return nil }
            return Identity(info)
        }
    }

    func stop(closeTerminal: () -> Void) {
        // Never call SwiftTerm.terminate with a stale PID: it sends SIGTERM itself.
        if let current = Self.info(shell.pid), Identity(current) == shell { closeTerminal() }
        let started = ProcessInfo.processInfo.systemUptime
        var signalled: Set<Identity> = []
        // ponytail: bounded synchronous cleanup also serves applicationWillTerminate.
        // Move module-disable cleanup to a joined worker if its rare 2 s wait affects UX.
        while ProcessInfo.processInfo.systemUptime - started < 2 {
            let active = members
            if active.isEmpty, reapShell() { return }
            let signal = ProcessInfo.processInfo.systemUptime - started >= 1 ? SIGKILL : SIGTERM
            for target in active {
                guard let current = Self.info(target.pid), Identity(current) == target,
                    target.pid == shell.pid || getsid(target.pid) == shell.pid else { continue }
                if signal == SIGKILL || signalled.insert(target).inserted {
                    kill(target.pid, signal)
                }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        _ = reapShell()
    }

    private func reapShell() -> Bool {
        // Zombie process info may already be unavailable. waitpid still owns reaping;
        // keep the leader's PID reserved until the session's living jobs are gone.
        if let current = Self.info(shell.pid), Identity(current) != shell { return true }
        var status: Int32 = 0
        let result = waitpid(shell.pid, &status, WNOHANG)
        return result == shell.pid || (result == -1 && errno == ECHILD)
    }
}

final class TerminalPanelController: NSObject, LocalProcessTerminalViewDelegate {
    let panel: KeyablePanel
    let terminalView: LocalProcessTerminalView
    let surfaceView: PanelSurfaceView
    let menuButton: NSButton

    private let onShellEvent: (String) -> Void
    private let resizeHandleView: TerminalResizeHandleView
    private var restartPolicy = ShellRestartPolicy()
    private(set) var lastRestartReason = "Initial login shell"
    private var scheduledRestart: DispatchWorkItem?
    private var automaticallyRestartsShell = true
    private var shellSession: TerminalShellSession?

    init(
        initialFrame: NSRect, theme: Theme, menuTarget: AnyObject, menuAction: Selector,
        onShellEvent: @escaping (String) -> Void = { _ in },
        onResizeEnd: @escaping () -> Void = {}
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
        let resizeHandleView = TerminalResizeHandleView(
            frame: built.surfaceView.contentContainer.bounds)
        resizeHandleView.autoresizingMask = [.width, .height]
        resizeHandleView.excludedView = built.menuButton
        resizeHandleView.onResizeEnd = onResizeEnd
        resizeHandleView.isEnabled = false
        built.surfaceView.contentContainer.addSubview(resizeHandleView)
        self.resizeHandleView = resizeHandleView
        super.init()
        terminalView.processDelegate = self
        applyAppearance(theme, presentation: .compact)
    }

    func applyAppearance(_ theme: Theme, presentation: PanelPresentation) {
        surfaceView.apply(theme: theme, presentation: presentation)
        // ponytail: SwiftTerm's standalone overlay scroller keeps its knob visible even with no
        // scrollback, which reads as a stray bar under the menu button at the three-row compact
        // size. Hide it there; switch to a SwiftTerm scroller-visibility API once one exists.
        terminalScroller?.isHidden = presentation == .compact
    }

    private var terminalScroller: NSScroller? {
        terminalView.subviews.lazy.compactMap { $0 as? NSScroller }.first
    }

    var isCustomResizing: Bool { resizeHandleView.isResizing }

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
        resizeHandleView.isEnabled = enabled
    }

    func startShell() {
        lastRestartReason = "Terminal module enabled"
        automaticallyRestartsShell = true
        scheduledRestart?.cancel()
        restartPolicy.reset()
        startShellSession()
    }

    func ensureShellRunning() {
        guard !terminalView.process.running else { return }
        lastRestartReason = "Started after a stopped session"
        scheduledRestart?.cancel()
        restartPolicy.reset()
        startShellSession()
    }

    func stopShell() {
        automaticallyRestartsShell = false
        scheduledRestart?.cancel()
        stopShellSession()
    }

    private func stopShellSession() {
        shellSession?.stop { terminalView.terminate() }
        shellSession = nil
    }

    private func startShellSession() {
        guard automaticallyRestartsShell, !terminalView.process.running else { return }
        stopShellSession()
        scheduledRestart = nil
        terminalView.terminal.resetToInitialState()
        restartPolicy.recordStart(at: ProcessInfo.processInfo.systemUptime)
        terminalView.startProcess(
            executable: ShellEnvironment.executable,
            args: ["-l"],
            environment: ShellEnvironment.variables(),
            currentDirectory: NSHomeDirectory()
        )
        shellSession = TerminalShellSession(pid: terminalView.process.shellPid)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            self?.handleShellTermination(exitCode: exitCode)
        }
    }

    private func handleShellTermination(exitCode: Int32?) {
        guard automaticallyRestartsShell else { return }
        lastRestartReason = "Previous shell exited with status \(exitCode.map(String.init) ?? "unknown")"
        onShellEvent("shell exited with status \(exitCode.map(String.init) ?? "unknown")")
        guard restartPolicy.shouldRestart(afterExitAt: ProcessInfo.processInfo.systemUptime) else {
            lastRestartReason += "; stopped after repeated rapid exits"
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
