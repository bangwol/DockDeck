import Combine
import Foundation

enum UsageProviderID: String, CaseIterable, Codable, Identifiable {
    case codex
    case claude

    var id: Self { self }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var subtitle: String {
        switch self {
        case .codex: "OpenAI account limits"
        case .claude: "Claude Code status-line limits"
        }
    }
}

enum UsageFreshness: Equatable {
    case loading
    case live
    case stale
    case signIn
    case unavailable
    case setupClaude

    var label: String? {
        switch self {
        case .live: nil
        case .loading: "…"
        case .stale: "STALE"
        case .signIn: "SIGN IN"
        case .unavailable: "OFFLINE"
        case .setupClaude: "SET UP"
        }
    }
}

struct UsageWindow: Identifiable, Equatable {
    let durationMinutes: Int
    let usedPercent: Double
    let resetsAt: Date?
    let customLabel: String?

    init(
        durationMinutes: Int, usedPercent: Double, resetsAt: Date?, customLabel: String? = nil
    ) {
        self.durationMinutes = durationMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.customLabel = customLabel
    }

    var id: String { customLabel.map { "custom:\($0)" } ?? "duration:\(durationMinutes)" }
    var remainingPercent: Double { min(max(100 - usedPercent, 0), 100) }

    var label: String {
        if let customLabel { return customLabel }
        if durationMinutes % (24 * 60) == 0 {
            return "\(durationMinutes / (24 * 60))d"
        }
        if durationMinutes % 60 == 0 {
            return "\(durationMinutes / 60)h"
        }
        return "\(durationMinutes)m"
    }
}

struct UsageProviderSnapshot: Equatable {
    let windows: [UsageWindow]
    let freshness: UsageFreshness
    let detail: String?
}

struct ProviderUsage: Identifiable, Equatable {
    let id: UsageProviderID
    let name: String
    let windows: [UsageWindow]
    let freshness: UsageFreshness
    let detail: String?
}

enum UsageProviderError: LocalizedError {
    case executableNotFound
    case bridgeNotInstalled
    case authenticationRequired(String)
    case invalidResponse(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex CLI executable not found"
        case .bridgeNotInstalled:
            "Claude Code 2.1.80+ status-line bridge cache not found"
        case .authenticationRequired(let message), .invalidResponse(let message),
            .transport(let message):
            message
        }
    }
}

final class UsageStore: ObservableObject {
    @Published private(set) var providers: [ProviderUsage]

    private let codexProvider: CodexAppServerProvider
    private let claudeProvider: ClaudeStatuslineCacheProvider
    private let logger: (String) -> Void
    private var providerSnapshots: [UsageProviderID: ProviderUsage]
    private var enabledProviderIDs = Set(UsageProviderID.allCases)
    private var refreshTimer: Timer?
    private var started = false

    init(
        codexProvider: CodexAppServerProvider = CodexAppServerProvider(),
        claudeProvider: ClaudeStatuslineCacheProvider = ClaudeStatuslineCacheProvider(),
        logger: @escaping (String) -> Void = { _ in }
    ) {
        let initialProviders = UsageProviderID.allCases.map {
            ProviderUsage(
                id: $0, name: $0.title.uppercased(), windows: [],
                freshness: .loading, detail: nil)
        }
        providers = initialProviders
        providerSnapshots = Dictionary(uniqueKeysWithValues: initialProviders.map { ($0.id, $0) })
        self.codexProvider = codexProvider
        self.claudeProvider = claudeProvider
        self.logger = logger
    }

    func start() {
        guard !started else { return }
        started = true
        if enabledProviderIDs.contains(.codex) { startCodex() }
        if enabledProviderIDs.contains(.claude) { refreshClaude() }

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refresh() {
        guard started else { return }
        if enabledProviderIDs.contains(.codex) { codexProvider.refresh() }
        if enabledProviderIDs.contains(.claude) { refreshClaude() }
    }

    func stop() {
        guard started else { return }
        started = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        codexProvider.stop()
    }

    func setEnabledProviders(_ providerIDs: [UsageProviderID]) {
        let resolved = Set(providerIDs.isEmpty ? UsageProviderID.allCases : providerIDs)
        let previous = enabledProviderIDs
        enabledProviderIDs = resolved
        publishProviders()

        guard started else { return }
        if previous.contains(.codex) && !resolved.contains(.codex) {
            codexProvider.stop()
        } else if !previous.contains(.codex) && resolved.contains(.codex) {
            startCodex()
        }
        if !previous.contains(.claude) && resolved.contains(.claude) {
            refreshClaude()
        }
    }

    private func startCodex() {
        codexProvider.start { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.started, self.enabledProviderIDs.contains(.codex) else {
                    return
                }
                self.apply(result, providerID: .codex)
            }
        }
    }

    private func refreshClaude() {
        guard started, enabledProviderIDs.contains(.claude) else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.claudeProvider.read()
            DispatchQueue.main.async {
                guard self.started, self.enabledProviderIDs.contains(.claude) else { return }
                self.apply(result, providerID: .claude)
            }
        }
    }

    private func apply(
        _ result: Result<UsageProviderSnapshot, UsageProviderError>, providerID: UsageProviderID
    ) {
        guard let previous = providerSnapshots[providerID] else { return }

        switch result {
        case .success(let snapshot):
            providerSnapshots[providerID] = ProviderUsage(
                id: previous.id,
                name: previous.name,
                windows: snapshot.windows,
                freshness: snapshot.freshness,
                detail: snapshot.detail)
        case .failure(let error):
            let freshness: UsageFreshness
            switch error {
            case .bridgeNotInstalled:
                freshness = .setupClaude
            case .authenticationRequired:
                freshness = .signIn
            default:
                freshness = previous.windows.isEmpty ? .unavailable : .stale
            }
            providerSnapshots[providerID] = ProviderUsage(
                id: previous.id,
                name: previous.name,
                windows: previous.windows,
                freshness: freshness,
                detail: error.localizedDescription)
        }
        publishProviders()
        guard let current = providerSnapshots[providerID] else { return }
        let windows = current.windows.map {
            "\($0.label)=\(Int($0.remainingPercent.rounded()))% remaining"
        }.joined(separator: ",")
        logger("\(providerID) \(current.freshness) \(windows)")
    }

    private func publishProviders() {
        providers = UsageProviderID.allCases.compactMap { providerID in
            enabledProviderIDs.contains(providerID) ? providerSnapshots[providerID] : nil
        }
    }
}
