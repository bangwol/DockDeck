import ApplicationServices
import Combine
import Darwin
import Foundation

enum DiagnosticCheckID: String, CaseIterable, Identifiable {
    case codex
    case claude
    case github
    case accessibility
    case temperature
    case network

    var id: Self { self }
}

enum DiagnosticCheckState: Equatable {
    case checking
    case ready
    case warning
    case unavailable
}

struct DiagnosticCheckItem: Identifiable, Equatable {
    let id: DiagnosticCheckID
    let title: String
    let symbolName: String
    let state: DiagnosticCheckState
    let detail: String
    let checkedAt: Date?
    let lastSuccessfulAt: Date?
}

enum DiagnosticCommandRunner {
    static func exitsSuccessfully(
        _ executable: URL, arguments: [String], timeout: TimeInterval = 3
    ) -> Bool? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        if terminated.wait(timeout: .now() + max(timeout, 0.1)) == .timedOut {
            process.terminate()
            if terminated.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 0.5)
            }
            return nil
        }
        return process.terminationStatus == 0
    }
}

enum DiagnosticsChecker {
    static func run(
        now: Date = Date(), environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [DiagnosticCheckItem] {
        [
            cliCheck(
                id: .codex, title: "Codex", symbolName: "chevron.left.forwardslash.chevron.right",
                executable: CodexBinaryLocator.locate(environment: environment),
                arguments: ["login", "status"], now: now),
            cliCheck(
                id: .claude, title: "Claude Code", symbolName: "sparkles",
                executable: ClaudeBinaryLocator.locate(environment: environment),
                arguments: ["auth", "status"], now: now),
            cliCheck(
                id: .github, title: "GitHub CLI", symbolName: "point.3.connected.trianglepath.dotted",
                executable: locateExecutable(
                    named: "gh", overrideKey: "DOCKDECK_GH_PATH", environment: environment),
                arguments: ["auth", "status", "--hostname", "github.com"], now: now),
            item(
                id: .accessibility, title: "Accessibility", symbolName: "accessibility",
                ready: AXIsProcessTrusted(),
                readyDetail: "Dock tracking permission granted",
                failureDetail: "Grant permission in Privacy & Security", now: now),
            item(
                id: .temperature, title: "Temperature sensor", symbolName: "thermometer.medium",
                ready: InstalledTemperatureReader.isAvailable,
                readyDetail: "Signed Stats sensor helper available",
                failureDetail: "Numeric temperature unavailable; thermal pressure still works",
                now: now),
            networkCheck(now: now),
        ]
    }

    private static func cliCheck(
        id: DiagnosticCheckID, title: String, symbolName: String,
        executable: URL?, arguments: [String], now: Date
    ) -> DiagnosticCheckItem {
        guard let executable else {
            return DiagnosticCheckItem(
                id: id, title: title, symbolName: symbolName, state: .unavailable,
                detail: "Executable not found", checkedAt: now, lastSuccessfulAt: nil)
        }
        let status = DiagnosticCommandRunner.exitsSuccessfully(
            executable, arguments: arguments)
        return DiagnosticCheckItem(
            id: id,
            title: title,
            symbolName: symbolName,
            state: status == true ? .ready : .warning,
            detail: status == true
                ? "Installed and signed in"
                : status == false ? "Installed; sign-in required" : "Status check timed out",
            checkedAt: now,
            lastSuccessfulAt: status == true ? now : nil)
    }

    private static func item(
        id: DiagnosticCheckID, title: String, symbolName: String, ready: Bool,
        readyDetail: String, failureDetail: String, now: Date
    ) -> DiagnosticCheckItem {
        DiagnosticCheckItem(
            id: id, title: title, symbolName: symbolName,
            state: ready ? .ready : .warning,
            detail: ready ? readyDetail : failureDetail,
            checkedAt: now,
            lastSuccessfulAt: ready ? now : nil)
    }

    private static func networkCheck(now: Date) -> DiagnosticCheckItem {
        guard let counters = NetworkCounterReader.read() else {
            return DiagnosticCheckItem(
                id: .network, title: "Network", symbolName: "network",
                state: .warning, detail: "No active primary interface",
                checkedAt: now, lastSuccessfulAt: nil)
        }
        return DiagnosticCheckItem(
            id: .network, title: "Network", symbolName: "network",
            state: .ready, detail: "\(counters.interfaceName) is active",
            checkedAt: now, lastSuccessfulAt: now)
    }

    private static func locateExecutable(
        named name: String, overrideKey: String, environment: [String: String]
    ) -> URL? {
        var candidates = [environment[overrideKey]].compactMap { $0 }
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/\(name)" })
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/\(name)",
        ])
        var seen: Set<String> = []
        return candidates.first {
            seen.insert($0).inserted && FileManager.default.isExecutableFile(atPath: $0)
        }.map(URL.init(fileURLWithPath:))
    }
}

final class DiagnosticsStore: ObservableObject {
    @Published private(set) var items: [DiagnosticCheckItem]
    @Published private(set) var isRefreshing = false

    private let checker: () -> [DiagnosticCheckItem]
    private let queue: DispatchQueue

    init(
        checker: @escaping () -> [DiagnosticCheckItem] = { DiagnosticsChecker.run() },
        queue: DispatchQueue = DispatchQueue(label: "DockDeck.Diagnostics", qos: .utility)
    ) {
        self.checker = checker
        self.queue = queue
        items = DiagnosticCheckID.allCases.map {
            DiagnosticCheckItem(
                id: $0, title: Self.title(for: $0), symbolName: Self.symbol(for: $0),
                state: .checking, detail: "Not checked", checkedAt: nil,
                lastSuccessfulAt: nil)
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let previous = items
        queue.async { [weak self] in
            guard let self else { return }
            let results = self.checker()
            DispatchQueue.main.async {
                self.items = Self.merging(results, previous: previous)
                self.isRefreshing = false
            }
        }
    }

    static func merging(
        _ results: [DiagnosticCheckItem], previous: [DiagnosticCheckItem]
    ) -> [DiagnosticCheckItem] {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        return results.map { result in
            DiagnosticCheckItem(
                id: result.id,
                title: result.title,
                symbolName: result.symbolName,
                state: result.state,
                detail: result.detail,
                checkedAt: result.checkedAt,
                lastSuccessfulAt: result.lastSuccessfulAt
                    ?? previousByID[result.id]?.lastSuccessfulAt)
        }
    }

    private static func title(for id: DiagnosticCheckID) -> String {
        switch id {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .github: "GitHub CLI"
        case .accessibility: "Accessibility"
        case .temperature: "Temperature sensor"
        case .network: "Network"
        }
    }

    private static func symbol(for id: DiagnosticCheckID) -> String {
        switch id {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkles"
        case .github: "point.3.connected.trianglepath.dotted"
        case .accessibility: "accessibility"
        case .temperature: "thermometer.medium"
        case .network: "network"
        }
    }
}
