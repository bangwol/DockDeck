import Combine
import Foundation

struct GitHubInboxConfiguration: Codable, Equatable {
    static let refreshIntervals: [TimeInterval] = [5 * 60, 10 * 60, 15 * 60]
    static let defaultRefreshInterval: TimeInterval = 10 * 60

    var actionsRepository: String?
    var refreshInterval: TimeInterval

    init(
        actionsRepository: String? = nil,
        refreshInterval: TimeInterval = Self.defaultRefreshInterval
    ) {
        self.actionsRepository = actionsRepository
        self.refreshInterval = refreshInterval
        self = normalized()
    }

    func normalized() -> Self {
        Self(
            uncheckedRepository: ProjectPulseConfiguration.normalizedGitHubRepository(
                actionsRepository),
            refreshInterval: Self.refreshIntervals.min {
                abs($0 - refreshInterval) < abs($1 - refreshInterval)
            } ?? Self.defaultRefreshInterval)
    }

    private init(uncheckedRepository: String?, refreshInterval: TimeInterval) {
        actionsRepository = uncheckedRepository
        self.refreshInterval = refreshInterval
    }
}

struct GitHubInboxSnapshot: Equatable {
    let unreadCount: Int
    let mentionCount: Int
    let reviewRequestCount: Int
    let ciNotificationCount: Int
    let failedRunsLastSevenDays: Int?
    let actionsRepository: String?
    let observedAt: Date
}

enum GitHubInboxStatus: Equatable {
    case loading
    case ready
    case unavailable(String)
}

enum GitHubInboxError: LocalizedError {
    case cliUnavailable
    case requestFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .cliUnavailable: "Install and sign in to GitHub CLI"
        case .requestFailed: "GitHub account check failed"
        case .invalidOutput: "GitHub returned an invalid response"
        }
    }
}

enum GitHubInboxParser {
    private struct Notification: Decodable {
        let reason: String
    }

    private struct Run: Decodable {
        let conclusion: String?
        let createdAt: String
    }

    static func parseNotifications(
        _ data: Data, failedRuns: Int?, repository: String?, observedAt: Date
    ) throws -> GitHubInboxSnapshot {
        let notifications: [Notification]
        if let flat = try? JSONDecoder().decode([Notification].self, from: data) {
            notifications = flat
        } else if let pages = try? JSONDecoder().decode([[Notification]].self, from: data) {
            notifications = pages.flatMap { $0 }
        } else {
            throw GitHubInboxError.invalidOutput
        }
        return GitHubInboxSnapshot(
            unreadCount: notifications.count,
            mentionCount: notifications.filter {
                $0.reason == "mention" || $0.reason == "team_mention"
            }.count,
            reviewRequestCount: notifications.filter { $0.reason == "review_requested" }.count,
            ciNotificationCount: notifications.filter { $0.reason == "ci_activity" }.count,
            failedRunsLastSevenDays: failedRuns,
            actionsRepository: repository,
            observedAt: observedAt)
    }

    static func parseFailedRuns(_ data: Data, since: Date) throws -> Int {
        let runs: [Run]
        do {
            runs = try JSONDecoder().decode([Run].self, from: data)
        } catch {
            throw GitHubInboxError.invalidOutput
        }
        let formatter = ISO8601DateFormatter()
        let failures = Set(["failure", "timed_out", "startup_failure", "action_required"])
        return runs.filter { run in
            guard let createdAt = formatter.date(from: run.createdAt), createdAt >= since else {
                return false
            }
            return run.conclusion.map { failures.contains($0.lowercased()) } ?? false
        }.count
    }
}

protocol GitHubInboxReading {
    func read(configuration: GitHubInboxConfiguration, now: Date) throws
        -> GitHubInboxSnapshot
}

struct GitHubInboxClient: GitHubInboxReading {
    private static let environment = [
        "GH_PROMPT_DISABLED": "1",
        "NO_COLOR": "1",
        "PAGER": "cat",
    ]

    func read(
        configuration: GitHubInboxConfiguration, now: Date
    ) throws -> GitHubInboxSnapshot {
        guard let gh = ProjectPulseBinaryLocator.githubCLI() else {
            throw GitHubInboxError.cliUnavailable
        }
        let notifications: Data
        do {
            notifications = try GitHubCLIRequestBroker.shared.run(
                executableURL: gh,
                arguments: [
                    "api", "--paginate", "--slurp", "-X", "GET", "notifications",
                    "-f", "all=false", "-f", "participating=false", "-F", "per_page=100",
                ],
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
                environment: Self.environment,
                cacheKey: "inbox", cacheDuration: 30)
        } catch {
            throw GitHubInboxError.requestFailed
        }

        let repository = configuration.normalized().actionsRepository
        let failedRuns: Int?
        if let repository {
            failedRuns = readFailedRuns(gh: gh, repository: repository, now: now)
        } else {
            failedRuns = nil
        }
        return try GitHubInboxParser.parseNotifications(
            notifications, failedRuns: failedRuns, repository: repository, observedAt: now)
    }

    private func readFailedRuns(gh: URL, repository: String, now: Date) -> Int? {
        do {
            let output = try GitHubCLIRequestBroker.shared.run(
                executableURL: gh,
                arguments: [
                    "run", "list", "--repo", repository, "--limit", "100",
                    "--status", "failure", "--json", "conclusion,createdAt",
                ],
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
                environment: Self.environment,
                cacheKey: "failed-runs:\(repository)", cacheDuration: 30)
            return try GitHubInboxParser.parseFailedRuns(
                output, since: now.addingTimeInterval(-7 * 24 * 60 * 60))
        } catch {
            return nil
        }
    }
}

final class GitHubInboxStore: ObservableObject {
    @Published private(set) var snapshot: GitHubInboxSnapshot?
    @Published private(set) var status: GitHubInboxStatus

    private var configuration: GitHubInboxConfiguration
    private let reader: GitHubInboxReading
    private let queue: DispatchQueue
    private var timer: Timer?
    private var isRunning = false
    private var requestID: UUID?
    private var generation = 0
    private var refreshCadence = ModuleRefreshCadence(backgroundMultiplier: 3)

    init(
        configuration: GitHubInboxConfiguration = PanelSettings.githubInboxConfiguration,
        reader: GitHubInboxReading = GitHubInboxClient(),
        queue: DispatchQueue = DispatchQueue(label: "DockDeck.GitHubInbox", qos: .utility),
        initialSnapshot: GitHubInboxSnapshot? = nil
    ) {
        self.configuration = configuration.normalized()
        self.reader = reader
        self.queue = queue
        snapshot = initialSnapshot
        status = initialSnapshot == nil ? .loading : .ready
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        scheduleTimer()
    }

    func stop() {
        guard isRunning || timer != nil else { return }
        isRunning = false
        generation += 1
        timer?.invalidate()
        timer = nil
    }

    func updateConfiguration(_ configuration: GitHubInboxConfiguration) {
        let configuration = configuration.normalized()
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        generation += 1
        guard isRunning else { return }
        scheduleTimer()
        refresh()
    }

    func setRuntimeActivity(
        _ activity: ModuleRuntimeActivity, lowPowerMode: Bool
    ) {
        guard refreshCadence.update(activity: activity, lowPowerMode: lowPowerMode),
            isRunning
        else { return }
        scheduleTimer()
    }

    func refresh() {
        guard isRunning, requestID == nil else { return }
        let requestID = UUID()
        let generation = generation
        let configuration = configuration
        self.requestID = requestID
        if snapshot == nil { status = .loading }

        queue.async { [weak self] in
            guard let self else { return }
            let result = Result {
                try self.reader.read(configuration: configuration, now: Date())
            }
            DispatchQueue.main.async {
                guard self.requestID == requestID else { return }
                self.requestID = nil
                guard self.isRunning else { return }
                guard self.generation == generation else {
                    self.refresh()
                    return
                }
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.status = .ready
                case .failure(let error):
                    self.status = .unavailable(
                        (error as? LocalizedError)?.errorDescription
                            ?? "GitHub account check failed")
                }
            }
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard isRunning else {
            timer = nil
            return
        }
        let interval = refreshCadence.effectiveInterval(
            configuredInterval: configuration.refreshInterval)
        timer = .moduleRefreshTimer(interval: interval) { [weak self] in self?.refresh() }
    }
}
