import Combine
import Foundation

struct DockerConfiguration: Codable, Equatable {
    static let refreshIntervals: [TimeInterval] = [5, 10, 30]
    static let defaultRefreshInterval: TimeInterval = 10

    var refreshInterval: TimeInterval

    init(refreshInterval: TimeInterval = Self.defaultRefreshInterval) {
        self.refreshInterval = Self.refreshIntervals.min {
            abs($0 - refreshInterval) < abs($1 - refreshInterval)
        } ?? Self.defaultRefreshInterval
    }

    func normalized() -> Self { Self(refreshInterval: refreshInterval) }
}
struct DockerSnapshot: Equatable {
    let runningCount: Int
    let stoppedCount: Int
    let unhealthyCount: Int
    let cpuPercent: Double?
    let memoryBytes: Double?
    let observedAt: Date
}

enum DockerStatus: Equatable {
    case loading
    case ready
    case unavailable(String)
}

enum DockerError: LocalizedError {
    case cliUnavailable
    case daemonUnavailable
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .cliUnavailable: "Docker CLI not found"
        case .daemonUnavailable: "Docker daemon is not running"
        case .invalidOutput: "Docker returned an invalid response"
        }
    }
}

enum DockerOutputParser {
    private struct Container: Decodable {
        let state: String
        let status: String

        private enum CodingKeys: String, CodingKey {
            case state = "State"
            case status = "Status"
        }
    }

    private struct Stats: Decodable {
        let cpuPercent: String
        let memoryUsage: String

        private enum CodingKeys: String, CodingKey {
            case cpuPercent = "CPUPerc"
            case memoryUsage = "MemUsage"
        }
    }

    static func parseContainers(_ data: Data) throws -> (running: Int, stopped: Int, unhealthy: Int) {
        let containers: [Container] = try decodeLines(data)
        let running = containers.filter { $0.state.lowercased() == "running" }.count
        let unhealthy = containers.filter { $0.status.lowercased().contains("unhealthy") }.count
        return (running, max(containers.count - running, 0), unhealthy)
    }

    static func parseStats(_ data: Data) throws -> (cpuPercent: Double, memoryBytes: Double) {
        let stats: [Stats] = try decodeLines(data)
        var cpu = 0.0
        var memory = 0.0
        for item in stats {
            guard let cpuValue = percent(item.cpuPercent),
                let memoryValue = bytes(String(item.memoryUsage.split(separator: "/").first ?? ""))
            else { throw DockerError.invalidOutput }
            cpu += cpuValue
            memory += memoryValue
        }
        return (cpu, memory)
    }

    private static func decodeLines<Value: Decodable>(_ data: Data) throws -> [Value] {
        let lines = data.split(whereSeparator: { $0 == 0x0A || $0 == 0x0D })
        do {
            return try lines.map { try JSONDecoder().decode(Value.self, from: Data($0)) }
        } catch {
            throw DockerError.invalidOutput
        }
    }

    private static func percent(_ value: String) -> Double? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasSuffix("%"), let result = Double(value.dropLast()),
            result.isFinite, result >= 0
        else { return nil }
        return result
    }

    static func bytes(_ value: String) -> Double? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let unitIndex = value.firstIndex(where: { $0.isLetter }),
            let amount = Double(value[..<unitIndex]), amount.isFinite, amount >= 0
        else { return nil }
        let unit = value[unitIndex...].lowercased()
        let multiplier: Double
        switch unit {
        case "b": multiplier = 1
        case "kb": multiplier = 1_000
        case "kib": multiplier = 1_024
        case "mb": multiplier = 1_000_000
        case "mib": multiplier = 1_048_576
        case "gb": multiplier = 1_000_000_000
        case "gib": multiplier = 1_073_741_824
        case "tb": multiplier = 1_000_000_000_000
        case "tib": multiplier = 1_099_511_627_776
        default: return nil
        }
        return amount * multiplier
    }
}

enum DockerBinaryLocator {
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var candidates = [
            environment["DOCKDECK_DOCKER_PATH"],
            "/opt/homebrew/bin/docker", "/usr/local/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ].compactMap { $0 }
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/docker" })
        }
        var seen: Set<String> = []
        return candidates.first {
            seen.insert($0).inserted && FileManager.default.isExecutableFile(atPath: $0)
        }.map(URL.init(fileURLWithPath:))
    }
}

protocol DockerReading {
    func read(now: Date) throws -> DockerSnapshot
}

struct DockerClient: DockerReading {
    private static let environment = [
        "DOCKER_CLI_HINTS": "false",
        "NO_COLOR": "1",
    ]

    func read(now: Date) throws -> DockerSnapshot {
        guard let docker = DockerBinaryLocator.locate() else {
            throw DockerError.cliUnavailable
        }
        let containersData: Data
        do {
            containersData = try BoundedProcessRunner.run(
                executableURL: docker,
                arguments: ["ps", "-a", "--format", "{{json .}}"],
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
                environmentAdditions: Self.environment,
                timeout: 5)
        } catch {
            throw DockerError.daemonUnavailable
        }
        let counts = try DockerOutputParser.parseContainers(containersData)
        var cpuPercent: Double? = counts.running == 0 ? 0 : nil
        var memoryBytes: Double? = counts.running == 0 ? 0 : nil
        if counts.running > 0,
            let statsData = try? BoundedProcessRunner.run(
                executableURL: docker,
                arguments: ["stats", "--no-stream", "--format", "{{json .}}"],
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
                environmentAdditions: Self.environment,
                timeout: 5),
            let stats = try? DockerOutputParser.parseStats(statsData)
        {
            cpuPercent = stats.cpuPercent
            memoryBytes = stats.memoryBytes
        }
        return DockerSnapshot(
            runningCount: counts.running,
            stoppedCount: counts.stopped,
            unhealthyCount: counts.unhealthy,
            cpuPercent: cpuPercent,
            memoryBytes: memoryBytes,
            observedAt: now)
    }
}

final class DockerStore: ObservableObject {
    @Published private(set) var snapshot: DockerSnapshot?
    @Published private(set) var status: DockerStatus

    private var configuration: DockerConfiguration
    private let reader: DockerReading
    private let queue: DispatchQueue
    private var timer: Timer?
    private var isRunning = false
    private var requestID: UUID?
    private var generation = 0
    private var refreshCadence = ModuleRefreshCadence(backgroundMultiplier: 4)

    init(
        configuration: DockerConfiguration = PanelSettings.dockerConfiguration,
        reader: DockerReading = DockerClient(),
        queue: DispatchQueue = DispatchQueue(label: "DockDeck.Docker", qos: .utility),
        initialSnapshot: DockerSnapshot? = nil
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

    func updateConfiguration(_ configuration: DockerConfiguration) {
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
        self.requestID = requestID
        if snapshot == nil { status = .loading }
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.reader.read(now: Date()) }
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
                            ?? "Docker is unavailable")
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
