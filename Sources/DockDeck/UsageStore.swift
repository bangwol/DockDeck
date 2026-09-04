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
        case .claude: "Claude Code account limits"
        }
    }
}

enum UsageFreshness: Equatable {
    case loading
    case live
    case stale
    case signIn
    case unavailable
    case setupRequired

    var label: String? {
        switch self {
        case .live: nil
        case .loading: "…"
        case .stale: "STALE"
        case .signIn: "SIGN IN"
        case .unavailable: "OFFLINE"
        case .setupRequired: "SET UP"
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
    let observedAt: Date
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
    case claudeExecutableNotFound
    case bridgeNotInstalled
    case authenticationRequired(String)
    case invalidResponse(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex CLI executable not found"
        case .claudeExecutableNotFound:
            "Claude Code executable not found"
        case .bridgeNotInstalled:
            "Claude Code status-line bridge cache not found"
        case .authenticationRequired(let message), .invalidResponse(let message),
            .transport(let message):
            message
        }
    }
}

final class UsageStore: ObservableObject {
    private static let refreshInterval: TimeInterval = 60
    private static let manualProbeMinimumInterval: TimeInterval = 60
    private static let defaultClaudeProbeTimeout: TimeInterval = 30

    @Published private(set) var providers: [ProviderUsage]

    private let codexProvider: CodexAppServerProvider
    private let claudeProvider: ClaudeStatuslineCacheProvider
    private let claudeCommandProvider: ClaudeUsageCommandReading
    private let nextClaudeProbeDelay: () -> TimeInterval
    private let claudeProbeTimeout: TimeInterval
    private let claudeProbeQueue: DispatchQueue
    private let uptime: () -> TimeInterval
    private let logger: (String) -> Void
    private var providerSnapshots: [UsageProviderID: ProviderUsage]
    private var claudeBridgeSnapshot: UsageProviderSnapshot?
    private var claudeCommandSnapshot: UsageProviderSnapshot?
    private var claudeProbeError: UsageProviderError?
    private var enabledProviderIDs = Set(UsageProviderID.allCases)
    private var refreshTimer: Timer?
    private var claudeProbeTimer: Timer?
    private var claudeProbeWatchdogTimer: Timer?
    private var claudeProbeInFlight = false
    private var claudeProbeGeneration = 0
    private var lastClaudeProbeUptime: TimeInterval?
    private var started = false
    private var systemRefreshActive = true
    private var claudeRefreshMode = ClaudeUsageRefreshMode.automatic
    private var refreshCadence = ModuleRefreshCadence(backgroundMultiplier: 5)

    init(
        codexProvider: CodexAppServerProvider = CodexAppServerProvider(),
        claudeProvider: ClaudeStatuslineCacheProvider = ClaudeStatuslineCacheProvider(),
        claudeCommandProvider: ClaudeUsageCommandReading = ClaudeUsageCommandProvider(),
        nextClaudeProbeDelay: @escaping () -> TimeInterval = {
            ClaudeUsageProbeSchedule.delay(unitValue: Double.random(in: 0...1))
        },
        claudeProbeTimeout: TimeInterval = UsageStore.defaultClaudeProbeTimeout,
        claudeProbeQueue: DispatchQueue = DispatchQueue(
            label: "DockDeck.ClaudeUsageProbe", qos: .utility),
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        logger: @escaping (String) -> Void = { _ in },
        initialProviders: [ProviderUsage]? = nil
    ) {
        let initialProviders = initialProviders ?? UsageProviderID.allCases.map {
            ProviderUsage(
                id: $0, name: $0.title.uppercased(), windows: [],
                freshness: .loading, detail: nil)
        }
        providers = initialProviders
        providerSnapshots = Dictionary(uniqueKeysWithValues: initialProviders.map { ($0.id, $0) })
        self.codexProvider = codexProvider
        self.claudeProvider = claudeProvider
        self.claudeCommandProvider = claudeCommandProvider
        self.nextClaudeProbeDelay = nextClaudeProbeDelay
        self.claudeProbeTimeout = max(claudeProbeTimeout, 0.01)
        self.claudeProbeQueue = claudeProbeQueue
        self.uptime = uptime
        self.logger = logger
    }

    func start() {
        guard !started else { return }
        started = true
        if enabledProviderIDs.contains(.codex) { startCodex() }
        if enabledProviderIDs.contains(.claude), systemRefreshActive {
            refreshClaudeBridge()
            if claudeRefreshMode == .automatic { requestClaudeProbeWhenAvailable() }
        }

        scheduleRefreshTimer()
    }

    func refresh() {
        guard started, systemRefreshActive else { return }
        if enabledProviderIDs.contains(.codex) { codexProvider.refresh() }
        if enabledProviderIDs.contains(.claude) {
            refreshClaudeBridge()
            if claudeRefreshMode == .automatic {
                requestClaudeProbe(force: true, respectsCooldown: true)
            }
        }
    }

    func refreshClaudeUsageIfDue() {
        guard started, systemRefreshActive, enabledProviderIDs.contains(.claude) else {
            return
        }
        refreshClaudeBridge()
        if claudeRefreshMode == .automatic {
            requestClaudeProbe(force: false, respectsCooldown: true)
        }
    }

    func stop() {
        guard started else { return }
        started = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancelClaudeProbe()
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
        if previous.contains(.claude) && !resolved.contains(.claude) {
            cancelClaudeProbe()
        } else if !previous.contains(.claude) && resolved.contains(.claude),
            systemRefreshActive
        {
            refreshClaudeBridge()
            if claudeRefreshMode == .automatic { requestClaudeProbeWhenAvailable() }
        }
    }

    func setClaudeRefreshMode(_ mode: ClaudeUsageRefreshMode) {
        guard claudeRefreshMode != mode else { return }
        claudeRefreshMode = mode
        if mode == .statusLineOnly {
            cancelClaudeProbe()
            claudeCommandSnapshot = nil
            claudeProbeError = nil
            if let claudeBridgeSnapshot {
                apply(.success(claudeBridgeSnapshot), providerID: .claude)
            } else {
                resetClaudeProviderForBridge()
            }
            if started, systemRefreshActive, enabledProviderIDs.contains(.claude) {
                refreshClaudeBridge()
            }
        } else if started, systemRefreshActive, enabledProviderIDs.contains(.claude) {
            refreshClaudeBridge()
            requestClaudeProbeWhenAvailable()
        }
    }

    func setSystemRefreshActive(_ active: Bool) {
        guard systemRefreshActive != active else { return }
        systemRefreshActive = active
        if !active {
            refreshTimer?.invalidate()
            refreshTimer = nil
            cancelClaudeProbe()
            return
        }
        if enabledProviderIDs.contains(.codex) { codexProvider.refresh() }
        if enabledProviderIDs.contains(.claude) {
            refreshClaudeBridge()
            if claudeRefreshMode == .automatic { requestClaudeProbeWhenAvailable() }
        }
        scheduleRefreshTimer()
    }

    func setRuntimeActivity(
        _ activity: ModuleRuntimeActivity, lowPowerMode: Bool
    ) {
        guard refreshCadence.update(activity: activity, lowPowerMode: lowPowerMode),
            started
        else { return }
        scheduleRefreshTimer()
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

    private func refreshClaudeBridge() {
        guard started, enabledProviderIDs.contains(.claude) else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.claudeProvider.read()
            DispatchQueue.main.async {
                guard self.started, self.systemRefreshActive,
                    self.enabledProviderIDs.contains(.claude)
                else { return }
                switch result {
                case .success(let snapshot):
                    self.claudeBridgeSnapshot = snapshot
                    self.publishClaudeSources()
                case .failure(let error):
                    self.claudeBridgeSnapshot = nil
                    self.publishClaudeSources(fallbackError: error)
                }
            }
        }
    }

    private func requestClaudeProbe(force: Bool, respectsCooldown: Bool = false) {
        guard started, systemRefreshActive, claudeRefreshMode == .automatic,
            enabledProviderIDs.contains(.claude),
            !claudeProbeInFlight
        else { return }
        if !force, postponeClaudeProbeIfExhausted() { return }
        let currentUptime = uptime()
        if respectsCooldown, let lastClaudeProbeUptime,
            currentUptime - lastClaudeProbeUptime < Self.manualProbeMinimumInterval
        {
            scheduleClaudeProbeAfterCooldown(
                Self.manualProbeMinimumInterval - (currentUptime - lastClaudeProbeUptime))
            return
        }

        claudeProbeTimer?.invalidate()
        claudeProbeTimer = nil
        claudeProbeInFlight = true
        lastClaudeProbeUptime = currentUptime
        let generation = claudeProbeGeneration
        scheduleClaudeProbeWatchdog(generation: generation)
        claudeProbeQueue.async { [weak self] in
            guard let self else { return }
            let result = self.claudeCommandProvider.read(now: Date())
            DispatchQueue.main.async {
                guard self.started, self.systemRefreshActive,
                    self.enabledProviderIDs.contains(.claude),
                    self.claudeProbeGeneration == generation
                else { return }
                self.claudeProbeWatchdogTimer?.invalidate()
                self.claudeProbeWatchdogTimer = nil
                self.claudeProbeInFlight = false
                switch result {
                case .success(let snapshot):
                    self.claudeCommandSnapshot = snapshot
                    self.claudeProbeError = nil
                    self.publishClaudeSources()
                case .failure(let error):
                    self.claudeProbeError = error
                    self.publishClaudeSources(fallbackError: error)
                }
                self.scheduleClaudeProbe()
            }
        }
    }

    private func requestClaudeProbeWhenAvailable() {
        guard !postponeClaudeProbeIfExhausted() else { return }
        requestClaudeProbe(force: true, respectsCooldown: true)
    }

    private func postponeClaudeProbeIfExhausted() -> Bool {
        guard ClaudeUsageProbeSchedule.exhaustedDelay(
            windows: currentClaudeWindows, now: Date()) != nil
        else { return false }
        if claudeProbeTimer == nil { scheduleClaudeProbe() }
        return true
    }

    private var currentClaudeWindows: [UsageWindow] {
        ClaudeUsageSnapshotMerger.merge(
            [claudeBridgeSnapshot, claudeCommandSnapshot].compactMap { $0 }
        )?.windows ?? []
    }

    private func publishClaudeSources(fallbackError: UsageProviderError? = nil) {
        let snapshots = [claudeBridgeSnapshot, claudeCommandSnapshot].compactMap { $0 }
        if let snapshot = ClaudeUsageSnapshotMerger.merge(snapshots) {
            let error = claudeProbeError ?? (claudeCommandSnapshot == nil ? fallbackError : nil)
            guard let error else {
                apply(.success(snapshot), providerID: .claude)
                return
            }
            let freshness: UsageFreshness
            if case .authenticationRequired = error {
                freshness = .signIn
            } else {
                freshness = .stale
            }
            let details = [snapshot.detail, "Refresh failed: \(error.localizedDescription)"]
                .compactMap { $0 }
            apply(
                .success(UsageProviderSnapshot(
                    windows: snapshot.windows,
                    freshness: freshness,
                    detail: details.joined(separator: " · "),
                    observedAt: snapshot.observedAt)),
                providerID: .claude)
        } else if let fallbackError {
            apply(.failure(fallbackError), providerID: .claude)
        }
    }

    private func cancelClaudeProbe() {
        claudeProbeTimer?.invalidate()
        claudeProbeTimer = nil
        claudeProbeWatchdogTimer?.invalidate()
        claudeProbeWatchdogTimer = nil
        claudeProbeGeneration += 1
        claudeProbeInFlight = false
        claudeCommandProvider.cancel()
    }

    private func scheduleClaudeProbeWatchdog(generation: Int) {
        claudeProbeWatchdogTimer?.invalidate()
        let timer = Timer(timeInterval: claudeProbeTimeout, repeats: false) { [weak self] _ in
            guard let self, self.claudeProbeInFlight,
                self.claudeProbeGeneration == generation
            else { return }
            self.claudeProbeGeneration += 1
            self.claudeProbeInFlight = false
            self.claudeProbeWatchdogTimer = nil
            self.claudeCommandProvider.cancel()
            let error = UsageProviderError.transport("Claude /usage refresh timed out")
            self.claudeProbeError = error
            self.publishClaudeSources(fallbackError: error)
            self.scheduleClaudeProbe()
        }
        timer.tolerance = min(claudeProbeTimeout * 0.05, 1)
        RunLoop.main.add(timer, forMode: .common)
        claudeProbeWatchdogTimer = timer
    }

    private func resetClaudeProviderForBridge() {
        guard let previous = providerSnapshots[.claude] else { return }
        providerSnapshots[.claude] = ProviderUsage(
            id: previous.id, name: previous.name, windows: [],
            freshness: .loading, detail: nil)
        publishProviders()
    }

    private func scheduleClaudeProbe() {
        claudeProbeTimer?.invalidate()
        guard started, systemRefreshActive, claudeRefreshMode == .automatic,
            enabledProviderIDs.contains(.claude),
            !claudeProbeInFlight
        else {
            claudeProbeTimer = nil
            return
        }
        let proposed = nextClaudeProbeDelay()
        let interval = ClaudeUsageProbeSchedule.nextDelay(
            proposed: proposed, windows: currentClaudeWindows, now: Date())
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.claudeProbeTimer = nil
            self?.requestClaudeProbe(force: true)
        }
        timer.tolerance = min(interval * 0.05, 30)
        RunLoop.main.add(timer, forMode: .common)
        claudeProbeTimer = timer
    }

    private func scheduleClaudeProbeAfterCooldown(_ delay: TimeInterval) {
        guard started, systemRefreshActive, claudeRefreshMode == .automatic,
            enabledProviderIDs.contains(.claude)
        else { return }
        let fireDate = Date(timeIntervalSinceNow: max(delay, 0.1))
        if let claudeProbeTimer {
            if claudeProbeTimer.fireDate > fireDate { claudeProbeTimer.fireDate = fireDate }
            return
        }
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            self?.claudeProbeTimer = nil
            self?.requestClaudeProbe(force: true)
        }
        timer.tolerance = min(max(delay, 0.1) * 0.05, 1)
        RunLoop.main.add(timer, forMode: .common)
        claudeProbeTimer = timer
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
            case .bridgeNotInstalled, .executableNotFound, .claudeExecutableNotFound:
                freshness = .setupRequired
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

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        guard started, systemRefreshActive else {
            refreshTimer = nil
            return
        }
        let interval = refreshCadence.effectiveInterval(
            configuredInterval: Self.refreshInterval)
        refreshTimer = .moduleRefreshTimer(interval: interval) { [weak self] in
            guard let self, self.systemRefreshActive else { return }
            if self.enabledProviderIDs.contains(.codex) { self.codexProvider.refresh() }
            if self.enabledProviderIDs.contains(.claude) { self.refreshClaudeBridge() }
        }
    }
}
