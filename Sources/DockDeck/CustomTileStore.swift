import Foundation

enum CustomTileSource: String, Codable, CaseIterable, Identifiable {
    case executable
    case shortcut

    var id: Self { self }

    var title: String {
        switch self {
        case .executable: "Executable"
        case .shortcut: "Shortcut"
        }
    }
}

struct CustomTileConfiguration: Codable, Equatable {
    static let refreshIntervals: [TimeInterval] = [60, 5 * 60, 15 * 60]
    static let defaultRefreshInterval: TimeInterval = 5 * 60
    static let maximumTitleLength = 32
    static let maximumPathLength = 4_096
    static let maximumArgumentCount = 16
    static let maximumArgumentLength = 1_024
    static let maximumShortcutNameLength = 255

    var title: String
    var source: CustomTileSource
    var executablePath: String
    var arguments: [String]
    var shortcutName: String
    var refreshInterval: TimeInterval

    init(
        title: String = "Custom Tile",
        source: CustomTileSource = .executable,
        executablePath: String = "",
        arguments: [String] = [],
        shortcutName: String = "",
        refreshInterval: TimeInterval = Self.defaultRefreshInterval
    ) {
        self.title = title
        self.source = source
        self.executablePath = executablePath
        self.arguments = arguments
        self.shortcutName = shortcutName
        self.refreshInterval = refreshInterval
        self = normalized()
    }

    var isConfigured: Bool {
        switch source {
        case .executable: !executablePath.isEmpty
        case .shortcut: !shortcutName.isEmpty
        }
    }

    func normalized() -> Self {
        var value = self
        value.title = Self.singleLine(title, limit: Self.maximumTitleLength)
        if value.title.isEmpty { value.title = "Custom Tile" }
        value.executablePath = Self.singleLine(
            executablePath, limit: Self.maximumPathLength)
        value.arguments = Array(arguments.prefix(Self.maximumArgumentCount)).map {
            String($0.replacingOccurrences(of: "\0", with: "")
                .prefix(Self.maximumArgumentLength))
        }
        value.shortcutName = Self.singleLine(
            shortcutName, limit: Self.maximumShortcutNameLength)
        value.refreshInterval = Self.refreshIntervals.min {
            abs($0 - refreshInterval) < abs($1 - refreshInterval)
        } ?? Self.defaultRefreshInterval
        return value
    }

    private static func singleLine(_ value: String, limit: Int) -> String {
        let value = value.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value.prefix(limit))
    }
}

struct CustomTileContent: Equatable {
    let title: String
    let value: String
    let detail: String?
    let symbolName: String?
}

struct CustomTileSnapshot: Equatable {
    let content: CustomTileContent
    let observedAt: Date
}

enum CustomTileStatus: Equatable {
    case notConfigured
    case loading
    case ready
    case unavailable(String)
}

enum CustomTileError: LocalizedError, Equatable {
    case notConfigured
    case executableMustBeAbsolute
    case executableUnavailable
    case shortcutUnavailable
    case commandTimedOut
    case outputTooLarge
    case commandFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Configure a command or Shortcut"
        case .executableMustBeAbsolute: "Use an absolute executable path"
        case .executableUnavailable: "Executable is unavailable"
        case .shortcutUnavailable: "Shortcut is unavailable"
        case .commandTimedOut: "Tile command timed out"
        case .outputTooLarge: "Tile output exceeds 32 KB"
        case .commandFailed: "Tile command failed"
        case .invalidOutput: "Tile output is empty or invalid"
        }
    }
}

enum CustomTileOutputParser {
    static let maximumOutputBytes = 32 * 1_024
    private static let maximumValueLength = 48
    private static let maximumDetailLength = 96
    private static let maximumSymbolLength = 64

    private struct Payload: Decodable {
        let title: String?
        let value: String?
        let detail: String?
        let symbol: String?
    }

    static func parse(_ data: Data, fallbackTitle: String) throws -> CustomTileContent {
        guard data.count <= maximumOutputBytes else { throw CustomTileError.outputTooLarge }
        guard let raw = String(data: data, encoding: .utf8) else {
            throw CustomTileError.invalidOutput
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CustomTileError.invalidOutput }

        if text.first == "{" {
            guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8))
            else { throw CustomTileError.invalidOutput }
            guard let value = field(payload.value, limit: maximumValueLength) else {
                throw CustomTileError.invalidOutput
            }
            return CustomTileContent(
                title: field(payload.title, limit: CustomTileConfiguration.maximumTitleLength)
                    ?? fallbackTitle,
                value: value,
                detail: field(payload.detail, limit: maximumDetailLength),
                symbolName: symbol(payload.symbol))
        }

        let lines = text.split(whereSeparator: { $0.isNewline }).map(String.init)
        guard let value = lines.first.flatMap({ field($0, limit: maximumValueLength) }) else {
            throw CustomTileError.invalidOutput
        }
        return CustomTileContent(
            title: fallbackTitle,
            value: value,
            detail: lines.dropFirst().first.flatMap {
                field($0, limit: maximumDetailLength)
            },
            symbolName: nil)
    }

    private static func field(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let scalars = value.unicodeScalars.filter {
            $0.value >= 0x20 && $0.value != 0x7f
        }
        let result = String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return nil }
        return String(result.prefix(limit))
    }

    private static func symbol(_ value: String?) -> String? {
        guard let value = field(value, limit: maximumSymbolLength) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return value.unicodeScalars.allSatisfy(allowed.contains) ? value : nil
    }
}

protocol CustomTileReading {
    func read(configuration: CustomTileConfiguration, now: Date, cancellation: Progress?) throws -> CustomTileSnapshot
}

struct CustomTileClient: CustomTileReading {
    func read(
        configuration: CustomTileConfiguration, now: Date, cancellation: Progress? = nil
    ) throws -> CustomTileSnapshot {
        let configuration = configuration.normalized()
        guard configuration.isConfigured else { throw CustomTileError.notConfigured }

        let executable: URL
        let arguments: [String]
        switch configuration.source {
        case .executable:
            guard configuration.executablePath.hasPrefix("/") else {
                throw CustomTileError.executableMustBeAbsolute
            }
            guard FileManager.default.isExecutableFile(atPath: configuration.executablePath) else {
                throw CustomTileError.executableUnavailable
            }
            executable = URL(fileURLWithPath: configuration.executablePath)
            arguments = configuration.arguments
        case .shortcut:
            let path = "/usr/bin/shortcuts"
            guard FileManager.default.isExecutableFile(atPath: path) else {
                throw CustomTileError.shortcutUnavailable
            }
            executable = URL(fileURLWithPath: path)
            arguments = ["run", configuration.shortcutName]
        }

        let output: Data
        do {
            output = try BoundedProcessRunner.run(
                executableURL: executable,
                arguments: arguments,
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
                environmentAdditions: ["NO_COLOR": "1", "TERM": "dumb"],
                timeout: 5,
                maximumOutputBytes: CustomTileOutputParser.maximumOutputBytes,
                cancellation: cancellation, diagnosticSource: .customTile)
        } catch BoundedProcessError.timedOut {
            throw CustomTileError.commandTimedOut
        } catch BoundedProcessError.outputTooLarge {
            throw CustomTileError.outputTooLarge
        } catch {
            throw CustomTileError.commandFailed
        }
        return CustomTileSnapshot(
            content: try CustomTileOutputParser.parse(
                output, fallbackTitle: configuration.title),
            observedAt: now)
    }
}

final class CustomTileStore: ObservableObject {
    @Published private(set) var snapshot: CustomTileSnapshot?
    @Published private(set) var status: CustomTileStatus

    private var configuration: CustomTileConfiguration
    private let reader: CustomTileReading
    private let queue: DispatchQueue
    private var timer: Timer?
    private var delayedRefresh: DispatchWorkItem?
    private var isRunning = false
    private var requestID: UUID?
    private var cancellation: Progress?
    private var generation = 0
    private var refreshCadence = ModuleRefreshCadence(backgroundMultiplier: 3)

    init(
        configuration: CustomTileConfiguration = PanelSettings.customTileConfiguration,
        reader: CustomTileReading = CustomTileClient(),
        queue: DispatchQueue = DispatchQueue(label: "DockDeck.CustomTile", qos: .utility),
        initialSnapshot: CustomTileSnapshot? = nil
    ) {
        self.configuration = configuration.normalized()
        self.reader = reader
        self.queue = queue
        snapshot = initialSnapshot
        status = initialSnapshot == nil
            ? (self.configuration.isConfigured ? .loading : .notConfigured) : .ready
    }

    var isStale: Bool {
        if case .unavailable = status { return snapshot != nil }
        return false
    }

    var statusDescription: String {
        switch status {
        case .notConfigured: "Configure a command or Shortcut"
        case .loading: "Running tile command"
        case .ready: "Ready"
        case .unavailable(let message): "Refresh failed: \(message)"
        }
    }

    var accessibilitySummary: String {
        guard let snapshot else { return statusDescription }
        return [snapshot.content.title, snapshot.content.value, snapshot.content.detail,
                statusDescription,
                "Last success: \(snapshot.observedAt.formatted(date: .abbreviated, time: .shortened))"]
            .compactMap { $0 }.joined(separator: ", ")
    }

    func runOnce(configuration: CustomTileConfiguration) {
        updateConfiguration(configuration)
        refresh(allowsStopped: true)
    }

    deinit { timer?.invalidate(); cancellation?.cancel(); delayedRefresh?.cancel() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        scheduleTimer()
    }

    func stop() {
        guard isRunning || timer != nil || delayedRefresh != nil || requestID != nil else { return }
        isRunning = false
        generation += 1
        cancellation?.cancel()
        timer?.invalidate()
        timer = nil
        delayedRefresh?.cancel()
        delayedRefresh = nil
    }

    func updateConfiguration(_ configuration: CustomTileConfiguration) {
        let configuration = configuration.normalized()
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        snapshot = nil
        status = configuration.isConfigured ? .loading : .notConfigured
        generation += 1
        cancellation?.cancel()
        guard isRunning else { return }
        scheduleTimer()
        delayedRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.refresh() }
        delayedRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    func setRuntimeActivity(
        _ activity: ModuleRuntimeActivity, lowPowerMode: Bool
    ) {
        guard refreshCadence.update(activity: activity, lowPowerMode: lowPowerMode),
            isRunning
        else { return }
        scheduleTimer()
    }

    func refresh() { refresh(allowsStopped: false) }

    private func refresh(allowsStopped: Bool) {
        delayedRefresh?.cancel()
        delayedRefresh = nil
        guard (isRunning || allowsStopped), configuration.isConfigured else {
            if isRunning || allowsStopped { status = .notConfigured }
            return
        }
        guard requestID == nil else { return }
        let requestID = UUID()
        let generation = generation
        let configuration = configuration
        self.requestID = requestID
        let cancellation = Progress(totalUnitCount: 1)
        self.cancellation = cancellation
        let reader = reader
        if snapshot == nil || allowsStopped { status = .loading }

        queue.async { [weak self] in
            let result = Result {
                try reader.read(configuration: configuration, now: Date(), cancellation: cancellation)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestID == requestID else { return }
                self.requestID = nil
                self.cancellation = nil
                guard self.isRunning || allowsStopped else { return }
                guard self.generation == generation else {
                    if self.delayedRefresh == nil { self.refresh() }
                    return
                }
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.status = .ready
                case .failure(let error):
                    self.status = .unavailable(
                        (error as? LocalizedError)?.errorDescription
                            ?? "Tile command failed")
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
