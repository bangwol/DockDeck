import ApplicationServices
import AppKit
import Combine
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
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 3
    ) -> Bool? {
        do {
            _ = try BoundedProcessRunner.run(
                executableURL: executable,
                arguments: arguments,
                environment: CodexBinaryLocator.launchEnvironment(
                    for: executable, environment: environment),
                timeout: timeout,
                maximumOutputBytes: 64 * 1_024)
            return true
        } catch BoundedProcessError.nonZeroExit {
            return false
        } catch {
            return nil
        }
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
                arguments: ["login", "status"], environment: environment, now: now),
            cliCheck(
                id: .claude, title: "Claude Code", symbolName: "sparkles",
                executable: ClaudeBinaryLocator.locate(environment: environment),
                arguments: ["auth", "status"], environment: environment, now: now),
            cliCheck(
                id: .github, title: "GitHub CLI", symbolName: "point.3.connected.trianglepath.dotted",
                executable: locateExecutable(
                    named: "gh", overrideKey: "DOCKDECK_GH_PATH", environment: environment),
                arguments: ["auth", "status", "--hostname", "github.com"],
                environment: environment, now: now),
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
        executable: URL?, arguments: [String], environment: [String: String], now: Date
    ) -> DiagnosticCheckItem {
        guard let executable else {
            return DiagnosticCheckItem(
                id: id, title: title, symbolName: symbolName, state: .unavailable,
                detail: "Executable not found", checkedAt: now, lastSuccessfulAt: nil)
        }
        let status = DiagnosticCommandRunner.exitsSuccessfully(
            executable, arguments: arguments, environment: environment)
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

enum DiagnosticsReportBuilder {
    static func build(
        items: [DiagnosticCheckItem],
        runtime: ModuleRuntimeDiagnostics,
        appVersion: String,
        operatingSystem: String,
        architecture: String
    ) -> String {
        var lines = [
            "DockDeck diagnostics",
            "App: \(singleLine(appVersion))",
            "macOS: \(singleLine(operatingSystem))",
            "Architecture: \(singleLine(architecture))",
            "System: \(runtime.systemActive ? "active" : "paused")",
            "Cadence: \(runtime.constrained ? "reduced" : "normal")",
            "",
            "Integrations",
        ]
        for id in DiagnosticCheckID.allCases {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            var line = "- \(title(for: id)): \(title(for: item.state))"
            if let checkedAt = item.checkedAt { line += "; checked \(timestamp(checkedAt))" }
            if let lastSuccessfulAt = item.lastSuccessfulAt {
                line += "; last OK \(timestamp(lastSuccessfulAt))"
            }
            lines.append(line)
        }
        lines.append(contentsOf: ["", "Modules"])
        for definition in PanelModuleRegistry.all {
            guard let state = runtime.states[definition.id] else { continue }
            var line = "- \(definition.title): \(title(for: state))"
            if let changedAt = runtime.stateChangedAt[definition.id] {
                line += "; since \(timestamp(changedAt))"
            }
            lines.append(line)
        }
        lines.append("")
        lines.append("Details, paths, URLs, command output, and account identifiers are omitted.")
        return lines.joined(separator: "\n")
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

    private static func title(for state: DiagnosticCheckState) -> String {
        switch state {
        case .checking: "checking"
        case .ready: "ready"
        case .warning: "check"
        case .unavailable: "missing"
        }
    }

    private static func title(for state: ModuleRuntimeCoordinator.State) -> String {
        switch state {
        case .stopped: "disabled"
        case .suspended: "paused"
        case .background: "background"
        case .visible: "visible"
        }
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func singleLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(160)
            .description
    }
}

final class DiagnosticsStore: ObservableObject {
    @Published private(set) var items: [DiagnosticCheckItem]
    @Published private(set) var moduleRuntime: ModuleRuntimeDiagnostics
    @Published private(set) var isRefreshing = false

    private let checker: () -> [DiagnosticCheckItem]
    private let runtimeProvider: () -> ModuleRuntimeDiagnostics
    private let queue: DispatchQueue

    init(
        checker: @escaping () -> [DiagnosticCheckItem] = { DiagnosticsChecker.run() },
        runtimeProvider: @escaping () -> ModuleRuntimeDiagnostics = { .empty },
        queue: DispatchQueue = DispatchQueue(label: "DockDeck.Diagnostics", qos: .utility)
    ) {
        self.checker = checker
        self.runtimeProvider = runtimeProvider
        self.queue = queue
        moduleRuntime = runtimeProvider()
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
                self.moduleRuntime = self.runtimeProvider()
                self.isRefreshing = false
            }
        }
    }

    func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report(), forType: .string)
    }

    func report(
        appVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
        operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: String = DiagnosticsStore.architecture
    ) -> String {
        DiagnosticsReportBuilder.build(
            items: items, runtime: runtimeProvider(), appVersion: appVersion,
            operatingSystem: operatingSystem, architecture: architecture)
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

    private static var architecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }
}
