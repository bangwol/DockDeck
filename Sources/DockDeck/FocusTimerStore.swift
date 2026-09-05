import Foundation

enum FocusTimerPhase: String, Codable, Equatable {
    case focus
    case breakTime

    var title: String { self == .focus ? "FOCUS" : "BREAK" }
    var next: Self { self == .focus ? .breakTime : .focus }
}

enum FocusTimerMode: String, Codable, Equatable {
    case idle
    case running
    case paused
}

struct FocusTimerSettings: Codable, Equatable {
    static let focusDurations = [15, 25, 45, 60]
    static let breakDurations = [5, 10, 15]

    var focusMinutes = 25
    var breakMinutes = 5

    func normalized() -> Self {
        var settings = self
        settings.focusMinutes = Self.closest(focusMinutes, in: Self.focusDurations)
        settings.breakMinutes = Self.closest(breakMinutes, in: Self.breakDurations)
        return settings
    }

    func durationSeconds(for phase: FocusTimerPhase) -> Int {
        (phase == .focus ? focusMinutes : breakMinutes) * 60
    }

    private static func closest(_ value: Int, in options: [Int]) -> Int {
        let bounded = min(max(value, options[0]), options[options.count - 1])
        return options.min { abs($0 - bounded) < abs($1 - bounded) } ?? options[0]
    }
}

struct FocusTimerSession: Codable, Equatable {
    var phase: FocusTimerPhase
    var mode: FocusTimerMode
    var deadline: Date?
    var remainingSeconds: Int
    var totalSeconds: Int

    static func idle(settings: FocusTimerSettings, phase: FocusTimerPhase = .focus) -> Self {
        let duration = settings.normalized().durationSeconds(for: phase)
        return Self(
            phase: phase,
            mode: .idle,
            deadline: nil,
            remainingSeconds: duration,
            totalSeconds: duration)
    }

    func normalized(settings: FocusTimerSettings, now: Date = Date()) -> Self {
        let settings = settings.normalized()
        let defaultDuration = settings.durationSeconds(for: phase)
        let total = (1...(24 * 60 * 60)).contains(totalSeconds)
            ? totalSeconds : defaultDuration
        let remaining = min(max(remainingSeconds, 0), total)
        if mode == .running, let deadline,
            deadline.timeIntervalSinceReferenceDate.isFinite
        {
            return Self(
                phase: phase, mode: .running,
                deadline: min(deadline, now.addingTimeInterval(TimeInterval(total))),
                remainingSeconds: remaining, totalSeconds: total)
        }
        guard remaining > 0 else {
            return .idle(settings: settings, phase: phase)
        }
        return Self(
            phase: phase,
            mode: mode == .paused ? .paused : .idle,
            deadline: nil,
            remainingSeconds: remaining,
            totalSeconds: total)
    }
}

struct FocusTimerSnapshot: Equatable {
    let phase: FocusTimerPhase
    let mode: FocusTimerMode
    let remainingSeconds: Int
    let totalSeconds: Int

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(1 - Double(remainingSeconds) / Double(totalSeconds), 0), 1)
    }

    var timeLabel: String {
        let seconds = max(remainingSeconds, 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

final class FocusTimerStore: ObservableObject {
    @Published private(set) var snapshot: FocusTimerSnapshot

    private var settings: FocusTimerSettings
    private var session: FocusTimerSession
    private let onSessionChange: (FocusTimerSession) -> Void
    private let onCompletion: (FocusTimerPhase) -> Void
    private var displayTimer: Timer?
    private var completionTimer: Timer?
    private var isRuntimeActive = false
    private var refreshCadence = ModuleRefreshCadence(backgroundMultiplier: 15)

    init(
        settings: FocusTimerSettings = FocusTimerSettings(),
        session: FocusTimerSession? = nil,
        now: Date = Date(),
        onSessionChange: @escaping (FocusTimerSession) -> Void = { _ in },
        onCompletion: @escaping (FocusTimerPhase) -> Void = { _ in }
    ) {
        let settings = settings.normalized()
        self.settings = settings
        self.session = (session ?? .idle(settings: settings)).normalized(settings: settings, now: now)
        self.onSessionChange = onSessionChange
        self.onCompletion = onCompletion
        snapshot = Self.makeSnapshot(session: self.session, now: now)
    }

    func start() {
        guard !isRuntimeActive else { return }
        isRuntimeActive = true
        refresh()
        scheduleTimers()
    }

    func stop() {
        isRuntimeActive = false
        invalidateTimers()
    }

    func updateSettings(_ settings: FocusTimerSettings, now: Date = Date()) {
        let settings = settings.normalized()
        guard self.settings != settings else { return }
        self.settings = settings
        if session.mode == .idle {
            session = .idle(settings: settings, phase: session.phase)
            persistSession()
        }
        publish(now: now)
        scheduleTimers(now: now)
    }

    func replaceSession(_ session: FocusTimerSession?, now: Date = Date()) {
        self.session = (session ?? .idle(settings: settings)).normalized(settings: settings, now: now)
        persistSession()
        refresh(now: now)
    }

    func setRuntimeActivity(
        _ activity: ModuleRuntimeActivity, lowPowerMode: Bool
    ) {
        guard refreshCadence.update(activity: activity, lowPowerMode: lowPowerMode),
            isRuntimeActive
        else { return }
        scheduleTimers()
    }

    func toggle(now: Date = Date()) {
        _ = reconcileCompletion(now: now)
        switch session.mode {
        case .running:
            let remaining = remainingSeconds(now: now)
            session.mode = .paused
            session.deadline = nil
            session.remainingSeconds = remaining
        case .idle, .paused:
            if session.remainingSeconds <= 0 {
                session = .idle(settings: settings, phase: session.phase)
            }
            session.mode = .running
            session.deadline = now.addingTimeInterval(TimeInterval(session.remainingSeconds))
        }
        persistSession()
        publish(now: now)
        scheduleTimers(now: now)
    }

    func reset(now: Date = Date()) {
        session = .idle(settings: settings, phase: session.phase)
        persistSession()
        publish(now: now)
        scheduleTimers(now: now)
    }

    func skip(now: Date = Date()) {
        session = .idle(settings: settings, phase: session.phase.next)
        persistSession()
        publish(now: now)
        scheduleTimers(now: now)
    }

    func refresh(now: Date = Date()) {
        let completed = reconcileCompletion(now: now)
        publish(now: now)
        if completed { scheduleTimers(now: now) }
    }

    private func reconcileCompletion(now: Date) -> Bool {
        guard session.mode == .running, let deadline = session.deadline,
            deadline <= now
        else { return false }
        let completedPhase = session.phase
        session = .idle(settings: settings, phase: completedPhase.next)
        persistSession()
        onCompletion(completedPhase)
        return true
    }

    private func remainingSeconds(now: Date) -> Int {
        guard session.mode == .running, let deadline = session.deadline else {
            return session.remainingSeconds
        }
        return Int(min(max(ceil(deadline.timeIntervalSince(now)), 0), Double(session.totalSeconds)))
    }

    private func publish(now: Date) {
        snapshot = Self.makeSnapshot(session: session, now: now)
    }

    private static func makeSnapshot(
        session: FocusTimerSession, now: Date
    ) -> FocusTimerSnapshot {
        let remaining: Int
        if session.mode == .running, let deadline = session.deadline {
            remaining = Int(min(
                max(ceil(deadline.timeIntervalSince(now)), 0), Double(session.totalSeconds)))
        } else {
            remaining = session.remainingSeconds
        }
        return FocusTimerSnapshot(
            phase: session.phase,
            mode: session.mode,
            remainingSeconds: remaining,
            totalSeconds: session.totalSeconds)
    }

    private func persistSession() {
        onSessionChange(session)
    }

    private func scheduleTimers(now: Date = Date()) {
        invalidateTimers()
        guard isRuntimeActive, session.mode == .running, let deadline = session.deadline else {
            return
        }
        let displayInterval = refreshCadence.effectiveInterval(configuredInterval: 1)
        displayTimer = .moduleRefreshTimer(interval: displayInterval) { [weak self] in
            self?.refresh()
        }
        let completionInterval = max(deadline.timeIntervalSince(now), 0.1)
        let completionTimer = Timer(timeInterval: completionInterval, repeats: false) {
            [weak self] _ in self?.refresh()
        }
        completionTimer.tolerance = min(max(completionInterval * 0.01, 0.1), 1)
        RunLoop.main.add(completionTimer, forMode: .common)
        self.completionTimer = completionTimer
    }

    private func invalidateTimers() {
        displayTimer?.invalidate()
        displayTimer = nil
        completionTimer?.invalidate()
        completionTimer = nil
    }
}
