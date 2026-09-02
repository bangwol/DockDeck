import Darwin
import Foundation

struct ProjectPulseConfiguration: Codable, Equatable {
    static let refreshIntervals: [TimeInterval] = [30, 60, 5 * 60]
    static let defaultRefreshInterval: TimeInterval = 60
    static let maximumPathLength = 4_096

    var repositoryPath: String?
    var includesGitHubActions: Bool
    var refreshInterval: TimeInterval

    init(
        repositoryPath: String? = nil,
        includesGitHubActions: Bool = false,
        refreshInterval: TimeInterval = Self.defaultRefreshInterval
    ) {
        self.repositoryPath = repositoryPath
        self.includesGitHubActions = includesGitHubActions
        self.refreshInterval = refreshInterval
        self = normalized()
    }

    func normalized() -> Self {
        var configuration = self
        if let path = repositoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty, path.count <= Self.maximumPathLength, !path.contains("\0")
        {
            let normalized = ((path as NSString).expandingTildeInPath as NSString)
                .standardizingPath
            configuration.repositoryPath = normalized.hasPrefix("/") ? normalized : nil
        } else {
            configuration.repositoryPath = nil
        }
        configuration.refreshInterval = Self.refreshIntervals.min {
            abs($0 - refreshInterval) < abs($1 - refreshInterval)
        } ?? Self.defaultRefreshInterval
        return configuration
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
    let workflow: ProjectWorkflowSnapshot?
}

enum ProjectPulseStatus: Equatable {
    case notConfigured
    case loading
    case ready
    case failed(String)
}

enum ProjectPulseError: LocalizedError, Equatable {
    case gitUnavailable
    case repositoryUnavailable
    case notRepository
    case commandTimedOut
    case outputTooLarge
    case commandFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .gitUnavailable: "Git is unavailable"
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
    func read(configuration: ProjectPulseConfiguration) throws -> ProjectPulseSnapshot {
        let configuration = configuration.normalized()
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
            gitOutput = try ProjectPulseCommand.run(
                executableURL: git,
                arguments: [
                    "-C", path, "status", "--porcelain=v2", "--branch", "-z",
                    "--untracked-files=normal",
                ],
                currentDirectoryURL: repositoryURL)
        } catch let error as ProjectPulseError {
            if error == .commandFailed { throw ProjectPulseError.notRepository }
            throw error
        }

        let repositoryName = repositoryURL.lastPathComponent.isEmpty
            ? "Repository" : repositoryURL.lastPathComponent
        let gitSnapshot = try GitPorcelainV2Parser.parse(
            gitOutput, repositoryName: repositoryName)
        let workflow = configuration.includesGitHubActions
            ? readWorkflow(in: repositoryURL) : nil
        return ProjectPulseSnapshot(git: gitSnapshot, workflow: workflow)
    }

    private func readWorkflow(in repositoryURL: URL) -> ProjectWorkflowSnapshot {
        guard let gh = ProjectPulseBinaryLocator.githubCLI() else {
            return ProjectWorkflowSnapshot(state: .unavailable, title: "Install gh for Actions")
        }
        do {
            let output = try ProjectPulseCommand.run(
                executableURL: gh,
                arguments: [
                    "run", "list", "--limit", "1", "--json",
                    "status,conclusion,name,displayTitle",
                ],
                currentDirectoryURL: repositoryURL,
                environment: ["GH_PROMPT_DISABLED": "1", "NO_COLOR": "1", "PAGER": "cat"])
            return try GitHubRunParser.parse(output)
                ?? ProjectWorkflowSnapshot(state: .neutral, title: "No workflow runs")
        } catch {
            return ProjectWorkflowSnapshot(
                state: .unavailable, title: "Actions unavailable")
        }
    }
}

enum GitPorcelainV2Parser {
    static func parse(_ data: Data, repositoryName: String) throws -> ProjectGitSnapshot {
        guard data.count <= ProjectPulseCommand.maximumOutputBytes,
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

enum ProjectPulseCommand {
    static let maximumOutputBytes = 1_048_576

    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment additions: [String: String] = [:],
        timeout: TimeInterval = 8
    ) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        var environment = ProcessInfo.processInfo.environment
        additions.forEach { environment[$0.key] = $0.value }
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let capture = ProjectPulseCommandCapture()
        let reads = DispatchGroup()
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            capture.setOutput(outputPipe.fileHandleForReading.readDataToEndOfFile())
            reads.leave()
        }
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            capture.setError(errorPipe.fileHandleForReading.readDataToEndOfFile())
            reads.leave()
        }

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            reads.wait()
            throw ProjectPulseError.commandFailed
        }

        if terminated.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if terminated.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 1)
            }
            reads.wait()
            throw ProjectPulseError.commandTimedOut
        }
        reads.wait()
        guard capture.output.count <= maximumOutputBytes,
            capture.error.count <= maximumOutputBytes
        else { throw ProjectPulseError.outputTooLarge }
        guard process.terminationStatus == 0 else { throw ProjectPulseError.commandFailed }
        return capture.output
    }
}

private final class ProjectPulseCommandCapture {
    private let lock = NSLock()
    private var storedOutput = Data()
    private var storedError = Data()

    var output: Data { lock.withLock { storedOutput } }
    var error: Data { lock.withLock { storedError } }

    func setOutput(_ data: Data) { lock.withLock { storedOutput = data } }
    func setError(_ data: Data) { lock.withLock { storedError = data } }
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
            : (self.configuration.repositoryPath == nil ? .notConfigured : .loading)
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
        let repositoryChanged = self.configuration.repositoryPath != configuration.repositoryPath
        self.configuration = configuration
        generation += 1
        if repositoryChanged { snapshot = nil }
        if configuration.repositoryPath == nil {
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
        guard configuration.repositoryPath != nil else {
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
        guard isRunning, configuration.repositoryPath != nil else {
            timer = nil
            return
        }
        let interval = refreshCadence.effectiveInterval(
            configuredInterval: configuration.refreshInterval)
        timer = .moduleRefreshTimer(interval: interval) { [weak self] in self?.refresh() }
    }
}
