import EventKit
import Foundation

enum ScheduleAuthorizationState: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
    case writeOnly

    var canRead: Bool { self == .granted }
}

struct ScheduleCalendarSource: Identifiable, Equatable {
    let id: String
    let title: String
}

struct ScheduleEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
}

struct ScheduleFetchResult: Equatable {
    let calendars: [ScheduleCalendarSource]
    let events: [ScheduleEventItem]
}

protocol ScheduleEventProviding: AnyObject {
    var authorizationState: ScheduleAuthorizationState { get }
    var onStoreChanged: (() -> Void)? { get set }

    func requestAccess(completion: @escaping (ScheduleAuthorizationState) -> Void)
    func suspend()
    func fetch(
        from startDate: Date,
        to endDate: Date,
        selectedCalendarIDs: Set<String>,
        includeAllDay: Bool,
        completion: @escaping (ScheduleFetchResult) -> Void)
}

final class EventKitScheduleProvider: ScheduleEventProviding {
    var authorizationState: ScheduleAuthorizationState {
        Self.currentAuthorizationState()
    }
    var onStoreChanged: (() -> Void)?

    private let queue = DispatchQueue(label: "com.dockdeck.schedule.eventkit", qos: .utility)
    private var eventStore: EKEventStore?
    private var observer: NSObjectProtocol?

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func requestAccess(completion: @escaping (ScheduleAuthorizationState) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let store = self.store()
            let finish: (Bool, Error?) -> Void = { [weak self, store] _, _ in
                self?.queue.async {
                    store.reset()
                    let state = Self.currentAuthorizationState()
                    DispatchQueue.main.async { completion(state) }
                }
            }
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents(completion: finish)
            } else {
                store.requestAccess(to: .event, completion: finish)
            }
        }
    }

    func suspend() {
        queue.async { [weak self] in
            guard let self else { return }
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            eventStore = nil
        }
    }

    func fetch(
        from startDate: Date,
        to endDate: Date,
        selectedCalendarIDs: Set<String>,
        includeAllDay: Bool,
        completion: @escaping (ScheduleFetchResult) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let store = self.store()
            let eventCalendars = store.calendars(for: .event)
            let calendars = eventCalendars
                .map {
                    ScheduleCalendarSource(
                        id: $0.calendarIdentifier,
                        title: Self.bounded($0.title, maximumLength: 60, fallback: "Calendar"))
                }
                .sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            let selectedCalendars: [EKCalendar]?
            if selectedCalendarIDs.isEmpty {
                selectedCalendars = nil
            } else {
                selectedCalendars = eventCalendars.filter {
                    selectedCalendarIDs.contains($0.calendarIdentifier)
                }
            }
            let events: [ScheduleEventItem]
            if selectedCalendarIDs.isEmpty || selectedCalendars?.isEmpty == false {
                let predicate = store.predicateForEvents(
                    withStart: startDate, end: endDate, calendars: selectedCalendars)
                events = store.events(matching: predicate)
                    .filter { $0.status != .canceled && (includeAllDay || !$0.isAllDay) }
                    .map(Self.item)
                    .sorted {
                        $0.startDate == $1.startDate
                            ? $0.endDate < $1.endDate : $0.startDate < $1.startDate
                    }
            } else {
                events = []
            }
            let result = ScheduleFetchResult(
                calendars: calendars, events: Array(events.prefix(100)))
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func currentAuthorizationState() -> ScheduleAuthorizationState {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess: return .granted
            case .writeOnly: return .writeOnly
            case .notDetermined: return .notDetermined
            case .denied: return .denied
            case .restricted: return .restricted
            @unknown default: return .denied
            }
        } else {
            switch status {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            case .denied: return .denied
            case .restricted: return .restricted
            default: return .denied
            }
        }
    }

    private func store() -> EKEventStore {
        if let eventStore { return eventStore }
        let store = EKEventStore()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.onStoreChanged?() }
        }
        eventStore = store
        return store
    }

    private static func item(_ event: EKEvent) -> ScheduleEventItem {
        let startDate = event.startDate ?? .distantPast
        let eventID = event.eventIdentifier ?? "event"
        return ScheduleEventItem(
            id: "\(eventID)|\(startDate.timeIntervalSinceReferenceDate)",
            title: bounded(event.title, maximumLength: 90, fallback: "Untitled event"),
            startDate: startDate,
            endDate: event.endDate ?? startDate,
            isAllDay: event.isAllDay,
            calendarTitle: bounded(
                event.calendar?.title, maximumLength: 60, fallback: "Calendar"))
    }

    private static func bounded(
        _ value: String?, maximumLength: Int, fallback: String
    ) -> String {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : String(value.prefix(maximumLength))
    }
}

enum ScheduleLoadStatus: Equatable {
    case idle
    case permissionRequired
    case loading
    case ready
}

final class ScheduleStore: ObservableObject {
    @Published private(set) var authorization: ScheduleAuthorizationState
    @Published private(set) var calendars: [ScheduleCalendarSource] = []
    @Published private(set) var events: [ScheduleEventItem] = []
    @Published private(set) var status: ScheduleLoadStatus = .idle

    private var selectedCalendarIDs: Set<String>
    private var includeAllDay: Bool
    private var refreshInterval: TimeInterval
    private var timer: Timer?
    private var generation = 0
    private var isRunning = false
    private let provider: ScheduleEventProviding

    init(
        selectedCalendarIDs: [String] = PanelSettings.scheduleCalendarIDs,
        includeAllDay: Bool = PanelSettings.scheduleIncludesAllDay,
        refreshInterval: TimeInterval = PanelSettings.scheduleRefreshInterval,
        provider: ScheduleEventProviding = EventKitScheduleProvider()
    ) {
        self.selectedCalendarIDs = Set(selectedCalendarIDs.filter { !$0.isEmpty })
        self.includeAllDay = includeAllDay
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
        self.provider = provider
        authorization = provider.authorizationState
        provider.onStoreChanged = { [weak self] in self?.refresh() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshAuthorization()
    }

    func stop() {
        guard isRunning || timer != nil else { return }
        isRunning = false
        generation += 1
        timer?.invalidate()
        timer = nil
        calendars = []
        events = []
        status = .idle
        provider.suspend()
    }

    func requestAccess() {
        guard authorization == .notDetermined else {
            refreshAuthorization()
            return
        }
        provider.requestAccess { [weak self] state in
            guard let self else { return }
            self.authorization = state
            if self.isRunning, state.canRead {
                self.refresh()
                self.scheduleTimer()
            } else {
                self.status = .permissionRequired
            }
        }
    }

    func refreshAuthorization() {
        authorization = provider.authorizationState
        guard isRunning else { return }
        if authorization.canRead {
            refresh()
            scheduleTimer()
        } else {
            generation += 1
            timer?.invalidate()
            timer = nil
            calendars = []
            events = []
            status = .permissionRequired
        }
    }

    func updateConfiguration(
        selectedCalendarIDs: [String], includeAllDay: Bool,
        refreshInterval: TimeInterval
    ) {
        self.selectedCalendarIDs = Set(selectedCalendarIDs.filter { !$0.isEmpty })
        self.includeAllDay = includeAllDay
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
        guard isRunning, authorization.canRead else { return }
        refresh()
        scheduleTimer()
    }

    func refresh(now: Date = Date()) {
        guard isRunning else { return }
        authorization = provider.authorizationState
        guard authorization.canRead else {
            refreshAuthorization()
            return
        }
        generation += 1
        let generation = generation
        status = .loading
        provider.fetch(
            from: now.addingTimeInterval(-12 * 60 * 60),
            to: now.addingTimeInterval(48 * 60 * 60),
            selectedCalendarIDs: selectedCalendarIDs,
            includeAllDay: includeAllDay
        ) { [weak self] result in
            guard let self, self.isRunning, generation == self.generation else { return }
            self.calendars = result.calendars
            self.events = result.events
            self.status = .ready
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard isRunning, authorization.canRead else {
            timer = nil
            return
        }
        timer = .moduleRefreshTimer(interval: refreshInterval) { [weak self] in self?.refresh() }
    }

    private static func resolvedRefreshInterval(_ value: TimeInterval) -> TimeInterval {
        PanelSettings.scheduleRefreshIntervals.min(by: {
            abs($0 - value) < abs($1 - value)
        }) ?? PanelSettings.defaultScheduleRefreshInterval
    }
}

enum SchedulePresentationMode: Equatable {
    case current
    case upcoming
}

struct SchedulePresentation: Equatable {
    let event: ScheduleEventItem
    let mode: SchedulePresentationMode
    let progress: Double
}

enum ScheduleTimeline {
    static func presentation(
        events: [ScheduleEventItem], now: Date
    ) -> SchedulePresentation? {
        let active = events.filter { $0.startDate <= now && $0.endDate > now }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return !$0.isAllDay }
                return $0.endDate < $1.endDate
            }
        if let event = active.first {
            return SchedulePresentation(
                event: event, mode: .current, progress: progress(event: event, now: now))
        }
        guard let event = events.filter({ $0.startDate > now }).min(by: {
            $0.startDate < $1.startDate
        }) else { return nil }
        return SchedulePresentation(event: event, mode: .upcoming, progress: 0)
    }

    static func progress(event: ScheduleEventItem, now: Date) -> Double {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        guard duration > 0 else { return 0 }
        return min(max(now.timeIntervalSince(event.startDate) / duration, 0), 1)
    }
}
