import Combine
import Foundation

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
    let id: String
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
            "Claude Code 2.1.251+ status-line bridge cache not found"
        case .authenticationRequired(let message), .invalidResponse(let message),
            .transport(let message):
            message
        }
    }
}

final class UsageStore: ObservableObject {
    @Published private(set) var providers: [ProviderUsage] = [
        ProviderUsage(
            id: "codex", name: "CODEX", windows: [],
            freshness: .loading, detail: nil),
        ProviderUsage(
            id: "claude", name: "CLAUDE", windows: [],
            freshness: .loading, detail: nil),
    ]

    private let codexProvider: CodexAppServerProvider
    private let claudeProvider: ClaudeStatuslineCacheProvider
    private let logger: (String) -> Void
    private var refreshTimer: Timer?
    private var started = false

    init(
        codexProvider: CodexAppServerProvider = CodexAppServerProvider(),
        claudeProvider: ClaudeStatuslineCacheProvider = ClaudeStatuslineCacheProvider(),
        logger: @escaping (String) -> Void = { _ in }
    ) {
        self.codexProvider = codexProvider
        self.claudeProvider = claudeProvider
        self.logger = logger
    }

    func start() {
        guard !started else { return }
        started = true
        codexProvider.start { [weak self] result in
            DispatchQueue.main.async {
                self?.apply(result, providerID: "codex")
            }
        }
        refreshClaude()

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refresh() {
        codexProvider.refresh()
        refreshClaude()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        codexProvider.stop()
        started = false
    }

    private func refreshClaude() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.claudeProvider.read()
            DispatchQueue.main.async {
                self.apply(result, providerID: "claude")
            }
        }
    }

    private func apply(
        _ result: Result<UsageProviderSnapshot, UsageProviderError>, providerID: String
    ) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        let previous = providers[index]

        switch result {
        case .success(let snapshot):
            providers[index] = ProviderUsage(
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
            providers[index] = ProviderUsage(
                id: previous.id,
                name: previous.name,
                windows: previous.windows,
                freshness: freshness,
                detail: error.localizedDescription)
        }
        let current = providers[index]
        let windows = current.windows.map {
            "\($0.label)=\(Int($0.remainingPercent.rounded()))% remaining"
        }.joined(separator: ",")
        logger("\(providerID) \(current.freshness) \(windows)")
    }
}
