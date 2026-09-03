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

struct ScheduleReminderListSource: Identifiable, Equatable {
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
    let joinURL: URL?

    init(
        id: String, title: String, startDate: Date, endDate: Date,
        isAllDay: Bool, calendarTitle: String, joinURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.joinURL = joinURL
    }
}

enum ScheduleMeetingLinkResolver {
    private static let supportedDomains = [
        "around.co", "bluejeans.com", "chime.aws", "facetime.apple.com",
        "meet.google.com", "meet.jit.si", "teams.live.com", "teams.microsoft.com",
        "webex.com", "whereby.com", "zoom.us",
    ]

    static func resolve(
        eventURL: URL?, location: String?, notes: String?
    ) -> URL? {
        if let eventURL, validated(eventURL) != nil { return eventURL }
        for text in [location, notes].compactMap({ $0 }) {
            let bounded = String(text.prefix(8_192))
            guard let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue)
            else { continue }
            let range = NSRange(bounded.startIndex..., in: bounded)
            var match: URL?
            detector.enumerateMatches(in: bounded, range: range) { result, _, stop in
                guard let url = result?.url, validated(url) != nil else { return }
                match = url
                stop.pointee = true
            }
            if let match { return match }
        }
        return nil
    }

    private static func validated(_ url: URL) -> URL? {
        guard url.absoluteString.count <= 2_048,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.user == nil, components.password == nil,
            let rawHost = components.host
        else { return nil }
        let host = rawHost.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: "."))
        guard supportedDomains.contains(where: {
            host == $0 || host.hasSuffix(".\($0)")
        }) else { return nil }
        return url
    }
}

struct ScheduleReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let dueDate: Date
    let isAllDay: Bool
    let listTitle: String
}

struct ScheduleFetchResult: Equatable {
    let calendars: [ScheduleCalendarSource]
    let events: [ScheduleEventItem]
    let reminderLists: [ScheduleReminderListSource]
    let reminders: [ScheduleReminderItem]
}

protocol ScheduleEventProviding: AnyObject {
    var authorizationState: ScheduleAuthorizationState { get }
    var reminderAuthorizationState: ScheduleAuthorizationState { get }
    var onStoreChanged: (() -> Void)? { get set }

    func requestAccess(completion: @escaping (ScheduleAuthorizationState) -> Void)
    func requestReminderAccess(completion: @escaping (ScheduleAuthorizationState) -> Void)
    func suspend()
    func fetch(
        from startDate: Date,
        to endDate: Date,
        reminderStartDate: Date,
        selectedCalendarIDs: Set<String>,
        selectedReminderListIDs: Set<String>,
        includeAllDay: Bool,
        includeReminders: Bool,
        completion: @escaping (ScheduleFetchResult) -> Void)
}

final class EventKitScheduleProvider: ScheduleEventProviding {
    var authorizationState: ScheduleAuthorizationState {
        Self.currentAuthorizationState(for: .event)
    }
    var reminderAuthorizationState: ScheduleAuthorizationState {
        Self.currentAuthorizationState(for: .reminder)
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
                    let state = Self.currentAuthorizationState(for: .event)
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

    func requestReminderAccess(completion: @escaping (ScheduleAuthorizationState) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let store = self.store()
            let finish: (Bool, Error?) -> Void = { [weak self, store] _, _ in
                self?.queue.async {
                    store.reset()
                    let state = Self.currentAuthorizationState(for: .reminder)
                    DispatchQueue.main.async { completion(state) }
                }
            }
            if #available(macOS 14.0, *) {
                store.requestFullAccessToReminders(completion: finish)
            } else {
                store.requestAccess(to: .reminder, completion: finish)
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
        reminderStartDate: Date,
        selectedCalendarIDs: Set<String>,
        selectedReminderListIDs: Set<String>,
        includeAllDay: Bool,
        includeReminders: Bool,
        completion: @escaping (ScheduleFetchResult) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let store = self.store()
            let eventCalendars = self.authorizationState.canRead
                ? store.calendars(for: .event) : []
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
            if self.authorizationState.canRead
                && (selectedCalendarIDs.isEmpty || selectedCalendars?.isEmpty == false)
            {
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

            guard includeReminders, self.reminderAuthorizationState.canRead else {
                self.finish(
                    calendars: calendars, events: events,
                    reminderLists: [], reminders: [], completion: completion)
                return
            }
            let reminderCalendars = store.calendars(for: .reminder)
            let reminderLists = reminderCalendars
                .map {
                    ScheduleReminderListSource(
                        id: $0.calendarIdentifier,
                        title: Self.bounded($0.title, maximumLength: 60, fallback: "Reminders"))
                }
                .sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            let selectedReminderCalendars: [EKCalendar]?
            if selectedReminderListIDs.isEmpty {
                selectedReminderCalendars = nil
            } else {
                selectedReminderCalendars = reminderCalendars.filter {
                    selectedReminderListIDs.contains($0.calendarIdentifier)
                }
            }
            guard selectedReminderListIDs.isEmpty
                || selectedReminderCalendars?.isEmpty == false
            else {
                self.finish(
                    calendars: calendars, events: events,
                    reminderLists: reminderLists, reminders: [], completion: completion)
                return
            }
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: reminderStartDate,
                ending: endDate,
                calendars: selectedReminderCalendars)
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                guard let self else { return }
                self.queue.async {
                    let items = (reminders ?? [])
                        .compactMap(Self.item)
                        .sorted { $0.dueDate < $1.dueDate }
                    self.finish(
                        calendars: calendars, events: events,
                        reminderLists: reminderLists, reminders: items,
                        completion: completion)
                }
            }
        }
    }

    static func currentAuthorizationState(
        for entityType: EKEntityType
    ) -> ScheduleAuthorizationState {
        let status = EKEventStore.authorizationStatus(for: entityType)
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
                event.calendar?.title, maximumLength: 60, fallback: "Calendar"),
            joinURL: ScheduleMeetingLinkResolver.resolve(
                eventURL: event.url, location: event.location, notes: event.notes))
    }

    private static func item(_ reminder: EKReminder) -> ScheduleReminderItem? {
        guard let components = reminder.dueDateComponents,
            let dueDate = Calendar.current.date(from: components)
        else { return nil }
        let reminderID = reminder.calendarItemIdentifier
        return ScheduleReminderItem(
            id: "\(reminderID)|\(dueDate.timeIntervalSinceReferenceDate)",
            title: bounded(reminder.title, maximumLength: 90, fallback: "Untitled reminder"),
            dueDate: dueDate,
            isAllDay: components.hour == nil && components.minute == nil,
            listTitle: bounded(
                reminder.calendar?.title, maximumLength: 60, fallback: "Reminders"))
    }

    private func finish(
        calendars: [ScheduleCalendarSource],
        events: [ScheduleEventItem],
        reminderLists: [ScheduleReminderListSource],
        reminders: [ScheduleReminderItem],
        completion: @escaping (ScheduleFetchResult) -> Void
    ) {
        let result = ScheduleFetchResult(
            calendars: calendars,
            events: Array(events.prefix(100)),
            reminderLists: reminderLists,
            reminders: Array(reminders.prefix(100)))
        DispatchQueue.main.async { completion(result) }
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
    @Published private(set) var reminderAuthorization: ScheduleAuthorizationState
    @Published private(set) var calendars: [ScheduleCalendarSource] = []
    @Published private(set) var events: [ScheduleEventItem] = []
    @Published private(set) var reminderLists: [ScheduleReminderListSource] = []
    @Published private(set) var reminders: [ScheduleReminderItem] = []
    @Published private(set) var status: ScheduleLoadStatus = .idle

    private var selectedCalendarIDs: Set<String>
    private var selectedReminderListIDs: Set<String>
    private var includeAllDay: Bool
    private var includeReminders: Bool
    private var refreshInterval: TimeInterval
    private var timer: Timer?
    private var generation = 0
    private var isRunning = false
    private let provider: ScheduleEventProviding
    private var refreshCadence = ModuleRefreshCadence()

    init(
        selectedCalendarIDs: [String] = PanelSettings.scheduleCalendarIDs,
        selectedReminderListIDs: [String] = PanelSettings.scheduleReminderListIDs,
        includeAllDay: Bool = PanelSettings.scheduleIncludesAllDay,
        includeReminders: Bool = PanelSettings.scheduleIncludesReminders,
        refreshInterval: TimeInterval = PanelSettings.scheduleRefreshInterval,
        provider: ScheduleEventProviding = EventKitScheduleProvider()
    ) {
        self.selectedCalendarIDs = Set(selectedCalendarIDs.filter { !$0.isEmpty })
        self.selectedReminderListIDs = Set(
            selectedReminderListIDs.filter { !$0.isEmpty })
        self.includeAllDay = includeAllDay
        self.includeReminders = includeReminders
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
        self.provider = provider
        authorization = provider.authorizationState
        reminderAuthorization = provider.reminderAuthorizationState
        provider.onStoreChanged = { [weak self] in self?.refresh() }
    }

    var canReadAnySource: Bool {
        authorization.canRead || (includeReminders && reminderAuthorization.canRead)
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
        reminderLists = []
        reminders = []
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
            self.resumeAfterAuthorizationChange()
        }
    }

    func requestReminderAccess() {
        guard reminderAuthorization == .notDetermined else {
            refreshAuthorization()
            return
        }
        provider.requestReminderAccess { [weak self] state in
            guard let self else { return }
            self.reminderAuthorization = state
            self.resumeAfterAuthorizationChange()
        }
    }

    func refreshAuthorization() {
        authorization = provider.authorizationState
        reminderAuthorization = provider.reminderAuthorizationState
        guard isRunning else { return }
        if canReadAnySource {
            refresh()
            scheduleTimer()
        } else {
            generation += 1
            timer?.invalidate()
            timer = nil
            calendars = []
            events = []
            reminderLists = []
            reminders = []
            status = .permissionRequired
        }
    }

    func updateConfiguration(
        selectedCalendarIDs: [String], selectedReminderListIDs: [String],
        includeAllDay: Bool, includeReminders: Bool,
        refreshInterval: TimeInterval
    ) {
        self.selectedCalendarIDs = Set(selectedCalendarIDs.filter { !$0.isEmpty })
        self.selectedReminderListIDs = Set(
            selectedReminderListIDs.filter { !$0.isEmpty })
        self.includeAllDay = includeAllDay
        self.includeReminders = includeReminders
        self.refreshInterval = Self.resolvedRefreshInterval(refreshInterval)
        guard isRunning else { return }
        refreshAuthorization()
    }

    func setRuntimeActivity(
        _ activity: ModuleRuntimeActivity, lowPowerMode: Bool
    ) {
        guard refreshCadence.update(activity: activity, lowPowerMode: lowPowerMode),
            isRunning, canReadAnySource
        else { return }
        scheduleTimer()
    }

    func refresh(now: Date = Date()) {
        guard isRunning else { return }
        authorization = provider.authorizationState
        reminderAuthorization = provider.reminderAuthorizationState
        guard canReadAnySource else {
            refreshAuthorization()
            return
        }
        generation += 1
        let generation = generation
        status = .loading
        provider.fetch(
            from: now.addingTimeInterval(-12 * 60 * 60),
            to: now.addingTimeInterval(48 * 60 * 60),
            reminderStartDate: now.addingTimeInterval(-7 * 24 * 60 * 60),
            selectedCalendarIDs: selectedCalendarIDs,
            selectedReminderListIDs: selectedReminderListIDs,
            includeAllDay: includeAllDay,
            includeReminders: includeReminders
        ) { [weak self] result in
            guard let self, self.isRunning, generation == self.generation else { return }
            self.calendars = result.calendars
            self.events = result.events
            self.reminderLists = result.reminderLists
            self.reminders = result.reminders
            self.status = .ready
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard isRunning, canReadAnySource else {
            timer = nil
            return
        }
        let interval = refreshCadence.effectiveInterval(
            configuredInterval: refreshInterval)
        timer = .moduleRefreshTimer(interval: interval) { [weak self] in self?.refresh() }
    }

    private func resumeAfterAuthorizationChange() {
        guard isRunning else {
            status = .permissionRequired
            return
        }
        if canReadAnySource {
            refresh()
            scheduleTimer()
        } else {
            status = .permissionRequired
        }
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

enum ScheduleReminderPresentationMode: Equatable {
    case overdue
    case upcoming
}

struct ScheduleReminderPresentation: Equatable {
    let reminder: ScheduleReminderItem
    let mode: ScheduleReminderPresentationMode
}

enum ScheduleAgendaPresentation: Equatable {
    case event(SchedulePresentation)
    case reminder(ScheduleReminderPresentation)
}

enum ScheduleAgendaTimeline {
    static func presentation(
        events: [ScheduleEventItem], reminders: [ScheduleReminderItem], now: Date
    ) -> ScheduleAgendaPresentation? {
        let currentEvent = ScheduleTimeline.presentation(events: events, now: now)
        if let currentEvent,
            currentEvent.mode == .current,
            !currentEvent.event.isAllDay
        {
            return .event(currentEvent)
        }

        if let overdue = reminders.filter({ $0.dueDate <= now }).max(by: {
            $0.dueDate < $1.dueDate
        }) {
            return .reminder(
                ScheduleReminderPresentation(reminder: overdue, mode: .overdue))
        }

        if let currentEvent, currentEvent.mode == .current {
            return .event(currentEvent)
        }

        let nextEvent = currentEvent
        let nextReminder = reminders.filter { $0.dueDate > now }.min(by: {
            $0.dueDate < $1.dueDate
        })
        switch (nextEvent, nextReminder) {
        case (let event?, let reminder?) where event.event.startDate <= reminder.dueDate:
            return .event(event)
        case (_, let reminder?):
            return .reminder(
                ScheduleReminderPresentation(reminder: reminder, mode: .upcoming))
        case (let event?, nil):
            return .event(event)
        case (nil, nil):
            return nil
        }
    }
}
