import AppKit
import Carbon
import Combine
import Foundation

enum MusicPlaybackState: String, Equatable {
    case stopped
    case paused
    case playing
    case fastForwarding = "fast forwarding"
    case rewinding

    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .paused: "Paused"
        case .playing: "Playing"
        case .fastForwarding: "Fast Forwarding"
        case .rewinding: "Rewinding"
        }
    }

    var isPlaying: Bool {
        switch self {
        case .playing, .fastForwarding, .rewinding: true
        case .stopped, .paused: false
        }
    }
}

struct MusicTrackSnapshot: Equatable {
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval?
    let position: TimeInterval?

    var progress: Double? {
        guard let duration, duration > 0, let position else { return nil }
        return min(max(position / duration, 0), 1)
    }
}

struct MusicPlaybackSnapshot: Equatable {
    let state: MusicPlaybackState
    let track: MusicTrackSnapshot?
    let observedAt: Date

    func estimatedTrack(at date: Date) -> MusicTrackSnapshot? {
        guard let track, state == .playing,
            let duration = track.duration, duration.isFinite, duration > 0,
            let position = track.position, position.isFinite
        else { return track }
        let elapsed = max(date.timeIntervalSince(observedAt), 0)
        guard elapsed.isFinite else { return track }
        return MusicTrackSnapshot(title: track.title, artist: track.artist, album: track.album,
            duration: duration, position: min(max(position + elapsed, 0), duration))
    }
}

enum MusicStatus: Equatable {
    case checking
    case notRunning
    case permissionRequired
    case permissionDenied
    case ready
    case unavailable
}

enum MusicCommand: Equatable {
    case previous
    case playPause
    case next
}

enum MusicAutomationAuthorization: Equatable {
    case authorized
    case needsConsent
    case denied
    case notRunning
    case unavailable

    static func resolved(_ status: OSStatus) -> Self {
        if status == noErr { return .authorized }
        if status == OSStatus(errAEEventWouldRequireUserConsent) { return .needsConsent }
        if status == OSStatus(errAEEventNotPermitted) { return .denied }
        if status == OSStatus(procNotFound) { return .notRunning }
        return .unavailable
    }
}

enum MusicAutomationError: Error {
    case invalidResponse
    case commandFailed
}

enum MusicAppleEventParser {
    private static let maximumTextLength = 160
    private static let maximumDuration: TimeInterval = 30 * 24 * 60 * 60

    static func parse(
        _ descriptor: NSAppleEventDescriptor, now: Date
    ) throws -> MusicPlaybackSnapshot {
        guard descriptor.numberOfItems >= 6,
            let stateValue = descriptor.atIndex(1)?.stringValue?.lowercased(),
            let state = MusicPlaybackState(rawValue: stateValue)
        else { throw MusicAutomationError.invalidResponse }

        let title = bounded(descriptor.atIndex(2)?.stringValue)
        let artist = bounded(descriptor.atIndex(3)?.stringValue)
        let album = bounded(descriptor.atIndex(4)?.stringValue)
        let duration = boundedTime(descriptor.atIndex(5)?.doubleValue)
        let rawPosition = boundedTime(descriptor.atIndex(6)?.doubleValue)
        let position = rawPosition.map { min($0, duration ?? $0) }
        let track = title.map {
            MusicTrackSnapshot(
                title: $0,
                artist: artist ?? "Unknown Artist",
                album: album,
                duration: duration,
                position: position)
        }
        return MusicPlaybackSnapshot(state: state, track: track, observedAt: now)
    }

    private static func bounded(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maximumTextLength))
    }

    private static func boundedTime(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value >= 0, value <= maximumDuration else {
            return nil
        }
        return value
    }
}

protocol MusicAutomationProviding {
    var isMusicRunning: Bool { get }
    func authorizationStatus(prompt: Bool) -> MusicAutomationAuthorization
    func readPlayback(now: Date) throws -> MusicPlaybackSnapshot
    func send(_ command: MusicCommand) throws
    func openMusic(completion: @escaping (Bool) -> Void)
}

final class MusicAutomationProvider: MusicAutomationProviding {
    static let bundleIdentifier = "com.apple.Music"

    private static let playbackScript = """
        with timeout of 3 seconds
            tell application id "com.apple.Music"
                set stateText to (player state as text)
                set trackName to ""
                set artistName to ""
                set albumName to ""
                set trackDuration to 0.0
                set trackPosition to 0.0
                try
                    set activeTrack to current track
                    set trackName to (name of activeTrack as text)
                    set artistName to (artist of activeTrack as text)
                    set albumName to (album of activeTrack as text)
                    set trackDuration to (duration of activeTrack as real)
                    set trackPosition to (player position as real)
                end try
                return {stateText, trackName, artistName, albumName, trackDuration, trackPosition}
            end tell
        end timeout
        """

    var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    func authorizationStatus(prompt: Bool) -> MusicAutomationAuthorization {
        guard Bundle.main.object(
            forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String != nil
        else { return .unavailable }
        let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleIdentifier)
        return .resolved(
            AEDeterminePermissionToAutomateTarget(
                target.aeDesc, typeWildCard, typeWildCard, prompt))
    }

    func readPlayback(now: Date) throws -> MusicPlaybackSnapshot {
        try MusicAppleEventParser.parse(
            execute(Self.playbackScript), now: now)
    }

    func send(_ command: MusicCommand) throws {
        let action: String
        switch command {
        case .previous: action = "previous track"
        case .playPause: action = "playpause"
        case .next: action = "next track"
        }
        _ = try execute(
            "with timeout of 3 seconds\n"
                + "tell application id \"com.apple.Music\" to \(action)\n"
                + "end timeout")
    }

    func openMusic(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: Self.bundleIdentifier)
            else {
                completion(false)
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(
                at: url, configuration: configuration
            ) { application, error in
                completion(application != nil && error == nil)
            }
        }
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw MusicAutomationError.commandFailed
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { throw MusicAutomationError.commandFailed }
        return result
    }
}

private enum MusicRefreshResult {
    case snapshot(MusicPlaybackSnapshot)
    case status(MusicStatus)
}

final class MusicStore: ObservableObject {
    static let refreshInterval: TimeInterval = 5
    static let commandDebounce: TimeInterval = 0.2

    @Published private(set) var snapshot: MusicPlaybackSnapshot?
    @Published private(set) var status: MusicStatus

    private let provider: MusicAutomationProviding
    private let queue: DispatchQueue
    private var timer: Timer?
    private var isRunning = false
    private var requestID: UUID?
    private var isConnecting = false
    private var generation = 0
    private var lastCommandUptime: TimeInterval?
    private var refreshCadence = ModuleRefreshCadence(
        backgroundMultiplier: 6, lowPowerMultiplier: 3)

    init(
        provider: MusicAutomationProviding = MusicAutomationProvider(),
        queue: DispatchQueue = DispatchQueue(label: "DockDeck.Music", qos: .utility),
        initialSnapshot: MusicPlaybackSnapshot? = nil,
        initialStatus: MusicStatus? = nil
    ) {
        self.provider = provider
        self.queue = queue
        snapshot = initialSnapshot
        status = initialStatus ?? (initialSnapshot == nil ? .checking : .ready)
    }

    var canControl: Bool { isRunning && status == .ready }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        scheduleTimer()
    }

    func stop() {
        guard isRunning || timer != nil || requestID != nil || isConnecting else { return }
        isRunning = false
        generation += 1
        requestID = nil
        isConnecting = false
        timer?.invalidate()
        timer = nil
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
        guard isRunning, requestID == nil, !isConnecting else { return }
        let requestID = UUID()
        let generation = generation
        self.requestID = requestID
        if snapshot == nil, status == .ready { status = .checking }

        queue.async { [weak self] in
            guard let self else { return }
            let result = self.readResult(prompt: false)
            DispatchQueue.main.async {
                guard self.requestID == requestID else { return }
                self.requestID = nil
                guard self.isRunning, self.generation == generation else { return }
                self.apply(result)
            }
        }
    }

    func requestAccess() {
        guard isRunning, !isConnecting else { return }
        isConnecting = true
        generation += 1
        requestID = nil
        status = .checking
        let generation = generation

        let authorize = { [weak self] in
            guard let self else { return }
            self.queue.async {
                let result = self.readResult(prompt: true)
                DispatchQueue.main.async {
                    guard self.isRunning, self.generation == generation else { return }
                    self.isConnecting = false
                    self.apply(result)
                }
            }
        }

        guard !provider.isMusicRunning else {
            authorize()
            return
        }
        provider.openMusic { [weak self] opened in
            DispatchQueue.main.async {
                guard let self, self.isRunning, self.generation == generation else { return }
                guard opened else {
                    self.isConnecting = false
                    self.apply(.status(.unavailable))
                    return
                }
                authorize()
            }
        }
    }

    func openMusic() {
        provider.openMusic { [weak self] opened in
            guard opened else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.refresh()
            }
        }
    }

    @discardableResult
    func send(
        _ command: MusicCommand,
        at currentUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        guard canControl, !isConnecting else { return false }
        if let lastCommandUptime,
            currentUptime - lastCommandUptime < Self.commandDebounce
        {
            return false
        }
        lastCommandUptime = currentUptime
        let generation = generation
        queue.async { [weak self] in
            guard let self else { return }
            let succeeded: Bool
            do {
                try self.provider.send(command)
                succeeded = true
            } catch {
                succeeded = false
            }
            DispatchQueue.main.async {
                guard self.isRunning, self.generation == generation else { return }
                guard succeeded else {
                    self.status = .unavailable
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.refresh()
                }
            }
        }
        return true
    }

    private func readResult(prompt: Bool) -> MusicRefreshResult {
        guard provider.isMusicRunning else { return .status(.notRunning) }
        switch provider.authorizationStatus(prompt: prompt) {
        case .authorized:
            do {
                return .snapshot(try provider.readPlayback(now: Date()))
            } catch {
                return .status(.unavailable)
            }
        case .needsConsent: return .status(.permissionRequired)
        case .denied: return .status(.permissionDenied)
        case .notRunning: return .status(.notRunning)
        case .unavailable: return .status(.unavailable)
        }
    }

    private func apply(_ result: MusicRefreshResult) {
        switch result {
        case .snapshot(let snapshot):
            self.snapshot = snapshot
            status = .ready
        case .status(let status):
            snapshot = nil
            self.status = status
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard isRunning else {
            timer = nil
            return
        }
        let interval = refreshCadence.effectiveInterval(
            configuredInterval: Self.refreshInterval)
        timer = .moduleRefreshTimer(interval: interval) { [weak self] in self?.refresh() }
    }
}
