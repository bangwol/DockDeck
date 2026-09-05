import Darwin
import Foundation

enum ProjectPulseSource: String, Codable, CaseIterable, Identifiable {
    case local
    case github

    var id: Self { self }

    var title: String {
        switch self {
        case .local: "Local"
        case .github: "GitHub"
        }
    }
}

enum GitHubPulseScope: String, Codable, CaseIterable, Identifiable {
    case repository
    case activity

    var id: Self { self }

    var title: String {
        switch self {
        case .repository: "Repository"
        case .activity: "My Activity"
        }
    }
}

struct ProjectPulseConfiguration: Codable, Equatable {
    static let refreshIntervals: [TimeInterval] = [30, 60, 5 * 60]
    static let defaultRefreshInterval: TimeInterval = 60
    static let maximumPathLength = Int(PATH_MAX) - 1

    var source: ProjectPulseSource
    var repositoryPath: String?
    var githubScope: GitHubPulseScope
    var githubRepository: String?
    var includesGitHubActions: Bool
    var refreshInterval: TimeInterval

    init(
        source: ProjectPulseSource = .local,
        repositoryPath: String? = nil,
        githubScope: GitHubPulseScope = .repository,
        githubRepository: String? = nil,
        includesGitHubActions: Bool = false,
        refreshInterval: TimeInterval = Self.defaultRefreshInterval
    ) {
        self.source = source
        self.repositoryPath = repositoryPath
        self.githubScope = githubScope
        self.githubRepository = githubRepository
        self.includesGitHubActions = includesGitHubActions
        self.refreshInterval = refreshInterval
        self = normalized()
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case repositoryPath
        case githubScope
        case githubRepository
        case includesGitHubActions
        case refreshInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(ProjectPulseSource.self, forKey: .source)
            ?? .local
        repositoryPath = try container.decodeIfPresent(String.self, forKey: .repositoryPath)
        githubScope = try container.decodeIfPresent(GitHubPulseScope.self, forKey: .githubScope)
            ?? .repository
        githubRepository = try container.decodeIfPresent(
            String.self, forKey: .githubRepository)
        includesGitHubActions = try container.decodeIfPresent(
            Bool.self, forKey: .includesGitHubActions) ?? false
        refreshInterval = try container.decodeIfPresent(
            TimeInterval.self, forKey: .refreshInterval) ?? Self.defaultRefreshInterval
        self = normalized()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(repositoryPath, forKey: .repositoryPath)
        try container.encode(githubScope, forKey: .githubScope)
        try container.encodeIfPresent(githubRepository, forKey: .githubRepository)
        try container.encode(includesGitHubActions, forKey: .includesGitHubActions)
        try container.encode(refreshInterval, forKey: .refreshInterval)
    }

    func normalized() -> Self {
        var configuration = self
        configuration.repositoryPath = Self.normalizedRepositoryPath(repositoryPath)
        configuration.githubRepository = Self.normalizedGitHubRepository(githubRepository)
        configuration.refreshInterval = Self.refreshIntervals.min {
            abs($0 - refreshInterval) < abs($1 - refreshInterval)
        } ?? Self.defaultRefreshInterval
        if configuration.source == .github, configuration.githubScope == .activity {
            configuration.refreshInterval = max(configuration.refreshInterval, 5 * 60)
        }
        return configuration
    }

    private static func normalizedRepositoryPath(_ value: String?) -> String? {
        guard var path = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty, !path.contains("\0"), path.utf8.count <= maximumPathLength else { return nil }
        if path.hasPrefix("~") {
            let prefix = path.prefix(while: { $0 != "/" })
            let home = prefix == "~" ? FileManager.default.homeDirectoryForCurrentUser.path
                : NSHomeDirectoryForUser(String(prefix.dropFirst()))
            guard let home else { return nil }
            path = home + path.dropFirst(prefix.count)
        }
        guard path.hasPrefix("/"), path.utf8.count <= maximumPathLength else { return nil }
        // Keep input within macOS PATH_MAX before platform path normalization.
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    var isConfigured: Bool {
        switch source {
        case .local: repositoryPath != nil
        case .github: githubScope == .activity || githubRepository != nil
        }
    }

    static func normalizedGitHubRepository(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty, value.count <= 201
        else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.count <= 100 }) else {
            return nil
        }
        guard parts.allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_."))
        guard parts.allSatisfy({ part in
            part.unicodeScalars.allSatisfy(allowed.contains)
        }) else { return nil }
        return parts.joined(separator: "/")
    }
}

extension ProjectPulseConfiguration {
    var favoriteKey: String {
        switch source {
        case .local: "local:\(repositoryPath ?? "")"
        case .github: "github:\(githubScope.rawValue):\(githubScope == .activity ? "" : githubRepository?.lowercased() ?? "")"
        }
    }

    var favoriteTitle: String {
        switch source {
        case .local: repositoryPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Local repository"
        case .github: githubScope == .activity ? "My GitHub activity" : githubRepository ?? "GitHub repository"
        }
    }

    static func favorites(_ configurations: [Self]) -> [Self] {
        var seen: Set<String> = []
        return Array(configurations.map { $0.normalized() }.filter {
            $0.isConfigured && ($0.repositoryPath?.utf8.count ?? 0) <= Self.maximumPathLength
                && seen.insert($0.favoriteKey).inserted
        }.prefix(3))
    }
}

struct ProjectGitSnapshot: Equatable {
    let repositoryName: String
    let branch: String
    let stagedCount: Int
    let modifiedCount: Int
    let untrackedCount: Int
    let conflictCount: Int
    let aheadCount: Int
    let behindCount: Int

    var changeCount: Int {
        stagedCount + modifiedCount + untrackedCount + conflictCount
    }
}

enum ProjectWorkflowState: Equatable {
    case success
    case failure
    case running
    case queued
    case neutral
    case unavailable
}

struct ProjectWorkflowSnapshot: Equatable {
    let state: ProjectWorkflowState
    let title: String
}

struct ProjectPulseSnapshot: Equatable {
    let git: ProjectGitSnapshot
    let github: ProjectGitHubSnapshot?
    let githubActivity: ProjectGitHubActivitySnapshot?
    let workflow: ProjectWorkflowSnapshot?

    init(
        git: ProjectGitSnapshot,
        github: ProjectGitHubSnapshot? = nil,
        githubActivity: ProjectGitHubActivitySnapshot? = nil,
        workflow: ProjectWorkflowSnapshot?
    ) {
        self.git = git
        self.github = github
        self.githubActivity = githubActivity
        self.workflow = workflow
    }
}

enum ProjectPulseStatus: Equatable {
    case notConfigured
    case loading
    case ready
    case failed(String)
}

enum ProjectPulseError: LocalizedError, Equatable {
    case gitUnavailable
    case githubCLIUnavailable
    case githubUnavailable
    case repositoryUnavailable
    case notRepository
    case commandTimedOut
    case outputTooLarge
    case commandFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .gitUnavailable: "Git is unavailable"
        case .githubCLIUnavailable: "Install GitHub CLI to use this source"
        case .githubUnavailable: "Sign in to GitHub CLI and try again"
        case .repositoryUnavailable: "Repository folder is unavailable"
        case .notRepository: "Choose a Git repository"
        case .commandTimedOut: "Repository check timed out"
        case .outputTooLarge: "Repository status is too large"
        case .commandFailed: "Repository check failed"
        case .invalidOutput: "Repository status could not be read"
        }
    }
}

protocol ProjectPulseReading {
    func read(configuration: ProjectPulseConfiguration) throws -> ProjectPulseSnapshot
}

struct ProjectPulseReader: ProjectPulseReading {
    private let github: GitHubProjectReading

    init(github: GitHubProjectReading = GitHubProjectClient()) {
        self.github = github
    }

    func read(configuration: ProjectPulseConfiguration) throws -> ProjectPulseSnapshot {
        let configuration = configuration.normalized()
        switch configuration.source {
        case .local:
            return try readLocal(configuration: configuration)
        case .github:
            return try readGitHub(configuration: configuration)
        }
    }

    private func readLocal(
        configuration: ProjectPulseConfiguration
    ) throws -> ProjectPulseSnapshot {
        guard let path = configuration.repositoryPath else {
            throw ProjectPulseError.repositoryUnavailable
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw ProjectPulseError.repositoryUnavailable }
        guard let git = ProjectPulseBinaryLocator.git() else {
            throw ProjectPulseError.gitUnavailable
        }

        let repositoryURL = URL(fileURLWithPath: path, isDirectory: true)
        let gitOutput: Data
        do {
            gitOutput = try BoundedProcessRunner.run(
                executableURL: git,
                arguments: [
                    "-C", path, "status", "--porcelain=v2", "--branch", "-z",
                    "--untracked-files=normal",
                ],
                currentDirectoryURL: repositoryURL)
        } catch BoundedProcessError.timedOut {
            throw ProjectPulseError.commandTimedOut
        } catch BoundedProcessError.outputTooLarge {
            throw ProjectPulseError.outputTooLarge
        } catch BoundedProcessError.nonZeroExit {
            throw ProjectPulseError.notRepository
        } catch {
            throw ProjectPulseError.commandFailed
        }

        let repositoryName = repositoryURL.lastPathComponent.isEmpty
            ? "Repository" : repositoryURL.lastPathComponent
        let gitSnapshot = try GitPorcelainV2Parser.parse(
            gitOutput, repositoryName: repositoryName)
        let workflow = configuration.includesGitHubActions
            ? github.readWorkflow(repository: nil, currentDirectoryURL: repositoryURL) : nil
        return ProjectPulseSnapshot(git: gitSnapshot, workflow: workflow)
    }

    private func readGitHub(
        configuration: ProjectPulseConfiguration
    ) throws -> ProjectPulseSnapshot {
        if configuration.githubScope == .activity {
            let activity = try github.readActivity(now: Date())
            return ProjectPulseSnapshot(
                git: ProjectGitSnapshot(
                    repositoryName: "@\(activity.login)",
                    branch: "7 days",
                    stagedCount: 0,
                    modifiedCount: 0,
                    untrackedCount: 0,
                    conflictCount: 0,
                    aheadCount: 0,
                    behindCount: 0),
                githubActivity: activity,
                workflow: nil)
        }
        guard let repository = configuration.githubRepository else {
            throw ProjectPulseError.githubUnavailable
        }
        let result = try github.readRepository(
            repository,
            includesWorkflow: configuration.includesGitHubActions,
            now: Date())
        return ProjectPulseSnapshot(
            git: ProjectGitSnapshot(
                repositoryName: result.repository.shortName,
                branch: result.repository.defaultBranch,
                stagedCount: 0,
                modifiedCount: 0,
                untrackedCount: 0,
                conflictCount: 0,
                aheadCount: 0,
                behindCount: 0),
            github: result.repository,
            workflow: result.workflow)
    }
}

enum GitPorcelainV2Parser {
    static func parse(_ data: Data, repositoryName: String) throws -> ProjectGitSnapshot {
        guard data.count <= BoundedProcessRunner.defaultMaximumOutputBytes,
            let text = String(data: data, encoding: .utf8)
        else { throw ProjectPulseError.invalidOutput }
        let separator: Character = text.contains("\0") ? "\0" : "\n"
        let records = text.split(separator: separator, omittingEmptySubsequences: true).map(String.init)

        var branch: String?
        var objectID: String?
        var ahead = 0
        var behind = 0
        var staged = 0
        var modified = 0
        var untracked = 0
        var conflicts = 0

        for record in records {
            if record.hasPrefix("# branch.head ") {
                branch = String(record.dropFirst("# branch.head ".count))
            } else if record.hasPrefix("# branch.oid ") {
                objectID = String(record.dropFirst("# branch.oid ".count))
            } else if record.hasPrefix("# branch.ab ") {
                for value in record.split(separator: " ").dropFirst(2) {
                    if value.first == "+" { ahead = Int(value.dropFirst()) ?? 0 }
                    if value.first == "-" { behind = Int(value.dropFirst()) ?? 0 }
                }
            } else if record.hasPrefix("? ") {
                untracked += 1
            } else if record.hasPrefix("u ") {
                conflicts += 1
            } else if record.hasPrefix("1 ") || record.hasPrefix("2 ") {
                let fields = record.split(separator: " ", maxSplits: 2)
                guard fields.count >= 2 else { continue }
                let status = Array(fields[1])
                if status.indices.contains(0), status[0] != "." { staged += 1 }
                if status.indices.contains(1), status[1] != "." { modified += 1 }
            }
        }

        guard var branch else { throw ProjectPulseError.invalidOutput }
        if branch == "(detached)" {
            branch = objectID.flatMap { $0 == "(initial)" ? nil : String($0.prefix(8)) }
                ?? "DETACHED"
        }
        return ProjectGitSnapshot(
            repositoryName: String(repositoryName.prefix(80)),
            branch: String(branch.prefix(120)),
            stagedCount: staged,
            modifiedCount: modified,
            untrackedCount: untracked,
            conflictCount: conflicts,
            aheadCount: max(ahead, 0),
            behindCount: max(behind, 0))
    }
}

enum GitHubRunParser {
    private struct Run: Decodable {
        let status: String
        let conclusion: String?
        let name: String?
        let displayTitle: String?
    }

    static func parse(_ data: Data) throws -> ProjectWorkflowSnapshot? {
        let runs: [Run]
        do {
            runs = try JSONDecoder().decode([Run].self, from: data)
        } catch {
            throw ProjectPulseError.invalidOutput
        }
        guard let run = runs.first else { return nil }
        let title = [run.displayTitle, run.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(120)) } ?? "GitHub Actions"
        return ProjectWorkflowSnapshot(
            state: state(status: run.status, conclusion: run.conclusion),
            title: title)
    }

    private static func state(status: String, conclusion: String?) -> ProjectWorkflowState {
        switch status.lowercased() {
        case "in_progress": return .running
        case "queued", "pending", "requested", "waiting": return .queued
        case "completed":
            switch conclusion?.lowercased() {
            case "success": return .success
            case "failure", "timed_out", "startup_failure", "action_required": return .failure
            default: return .neutral
            }
        default: return .neutral
        }
    }
}

enum ProjectPulseBinaryLocator {
    static func git() -> URL? {
        executable(named: "git", preferredPaths: ["/usr/bin/git"])
    }

    static func githubCLI(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        executable(
            named: "gh",
            preferredPaths: [
                environment["DOCKDECK_GH_PATH"], "/opt/homebrew/bin/gh", "/usr/local/bin/gh",
            ].compactMap { $0 },
            environment: environment)
    }

    private static func executable(
        named name: String,
        preferredPaths: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var paths = preferredPaths
        if let path = environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/\(name)" })
        }
        var seen: Set<String> = []
        return paths.first {
            seen.insert($0).inserted && FileManager.default.isExecutableFile(atPath: $0)
        }.map(URL.init(fileURLWithPath:))
    }
}

final class ProjectPulseStore: ObservableObject {
    @Published private(set) var snapshot: ProjectPulseSnapshot?
    @Published private(set) var status: ProjectPulseStatus

    private var configuration: ProjectPulseConfiguration
    private let reader: ProjectPulseReading
    private let queue = DispatchQueue(label: "DockDeck.ProjectPulse", qos: .utility)
    private var timer: Timer?
    private var isRunning = false
    private var activeReadID: UUID?
    private var generation = 0
    private var refreshCadence = ModuleRefreshCadence(backgroundMultiplier: 5)

    init(
        configuration: ProjectPulseConfiguration = PanelSettings.projectPulseConfiguration,
        reader: ProjectPulseReading = ProjectPulseReader(),
        initialSnapshot: ProjectPulseSnapshot? = nil
    ) {
        self.configuration = configuration.normalized()
        self.reader = reader
        snapshot = initialSnapshot
        status = initialSnapshot != nil
            ? .ready
            : (self.configuration.isConfigured ? .loading : .notConfigured)
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

    func updateConfiguration(_ configuration: ProjectPulseConfiguration) {
        let configuration = configuration.normalized()
        guard self.configuration != configuration else { return }
        let repositoryChanged = self.configuration.source != configuration.source
            || self.configuration.repositoryPath != configuration.repositoryPath
            || self.configuration.githubScope != configuration.githubScope
            || self.configuration.githubRepository != configuration.githubRepository
        self.configuration = configuration
        generation += 1
        if repositoryChanged { snapshot = nil }
        if !configuration.isConfigured {
            status = .notConfigured
        } else if snapshot == nil {
            status = .loading
        }
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
        guard isRunning else { return }
        guard configuration.isConfigured else {
            snapshot = nil
            status = .notConfigured
            return
        }
        guard activeReadID == nil else { return }
        let readID = UUID()
        let generation = generation
        let configuration = configuration
        activeReadID = readID
        if snapshot == nil { status = .loading }

        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.reader.read(configuration: configuration) }
            DispatchQueue.main.async {
                guard self.activeReadID == readID else { return }
                self.activeReadID = nil
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
                    self.status = .failed(
                        (error as? LocalizedError)?.errorDescription
                            ?? "Repository check failed")
                }
            }
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard isRunning, configuration.isConfigured else {
            timer = nil
            return
        }
        let interval = refreshCadence.effectiveInterval(
            configuredInterval: configuration.refreshInterval)
        timer = .moduleRefreshTimer(interval: interval) { [weak self] in self?.refresh() }
    }
}
