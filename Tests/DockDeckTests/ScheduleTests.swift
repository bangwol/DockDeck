import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class ScheduleTests: XCTestCase {
    func testTimelinePrefersTimedCurrentEventAndCalculatesProgress() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let allDay = event(
            id: "all-day", start: now.addingTimeInterval(-500),
            end: now.addingTimeInterval(500), isAllDay: true)
        let timed = event(
            id: "timed", start: now.addingTimeInterval(-100),
            end: now.addingTimeInterval(100))

        let presentation = try XCTUnwrap(
            ScheduleTimeline.presentation(events: [allDay, timed], now: now))

        XCTAssertEqual(presentation.event.id, "timed")
        XCTAssertEqual(presentation.mode, .current)
        XCTAssertEqual(presentation.progress, 0.5, accuracy: 0.001)
    }

    func testTimelineChoosesNextFutureEvent() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let later = event(
            id: "later", start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(900))
        let next = event(
            id: "next", start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(500))

        let presentation = try XCTUnwrap(
            ScheduleTimeline.presentation(events: [later, next], now: now))

        XCTAssertEqual(presentation.event.id, "next")
        XCTAssertEqual(presentation.mode, .upcoming)
        XCTAssertEqual(presentation.progress, 0)
    }

    func testAgendaPrefersCurrentEventOverOverdueReminder() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let current = event(
            id: "current", start: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(60))
        let reminder = reminder(id: "late", due: now.addingTimeInterval(-300))

        let presentation = try XCTUnwrap(
            ScheduleAgendaTimeline.presentation(
                events: [current], reminders: [reminder], now: now))

        guard case .event(let eventPresentation) = presentation else {
            return XCTFail("Expected the active event")
        }
        XCTAssertEqual(eventPresentation.event.id, "current")
    }

    func testAgendaShowsMostRecentOverdueReminderBeforeFutureItems() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let old = reminder(id: "old", due: now.addingTimeInterval(-600))
        let recent = reminder(id: "recent", due: now.addingTimeInterval(-60))
        let future = event(
            id: "future", start: now.addingTimeInterval(30),
            end: now.addingTimeInterval(90))

        let presentation = try XCTUnwrap(
            ScheduleAgendaTimeline.presentation(
                events: [future], reminders: [old, recent], now: now))

        guard case .reminder(let reminderPresentation) = presentation else {
            return XCTFail("Expected the overdue reminder")
        }
        XCTAssertEqual(reminderPresentation.reminder.id, "recent")
        XCTAssertEqual(reminderPresentation.mode, .overdue)
    }

    func testAgendaDoesNotLetAllDayEventHideOverdueReminder() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let allDay = event(
            id: "all-day", start: now.addingTimeInterval(-500),
            end: now.addingTimeInterval(500), isAllDay: true)
        let reminder = reminder(id: "late", due: now.addingTimeInterval(-60))

        let presentation = try XCTUnwrap(
            ScheduleAgendaTimeline.presentation(
                events: [allDay], reminders: [reminder], now: now))

        guard case .reminder(let reminderPresentation) = presentation else {
            return XCTFail("Expected the overdue reminder")
        }
        XCTAssertEqual(reminderPresentation.reminder.id, "late")
    }

    func testAgendaChoosesSoonerFutureItemAcrossSources() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let event = event(
            id: "event", start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(900))
        let reminder = reminder(id: "reminder", due: now.addingTimeInterval(300))

        let presentation = try XCTUnwrap(
            ScheduleAgendaTimeline.presentation(
                events: [event], reminders: [reminder], now: now))

        guard case .reminder(let reminderPresentation) = presentation else {
            return XCTFail("Expected the nearer reminder")
        }
        XCTAssertEqual(reminderPresentation.reminder.id, "reminder")
        XCTAssertEqual(reminderPresentation.mode, .upcoming)
    }

    func testStoreDoesNotFetchOrRequestBeforeExplicitAccessAction() {
        let provider = FakeScheduleProvider(authorization: .notDetermined)
        let store = ScheduleStore(provider: provider)

        store.start()

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertEqual(store.status, .permissionRequired)

        store.requestAccess()

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertEqual(store.authorization, .granted)
        store.stop()
        XCTAssertEqual(provider.suspendCount, 1)
    }

    func testStorePassesCalendarSelectionAndAllDaySetting() {
        let provider = FakeScheduleProvider(authorization: .granted)
        let store = ScheduleStore(
            selectedCalendarIDs: ["work"], includeAllDay: true,
            refreshInterval: 300, provider: provider)

        store.start()

        XCTAssertEqual(provider.lastSelectedCalendarIDs, ["work"])
        XCTAssertTrue(provider.lastIncludeAllDay)
        XCTAssertEqual(store.events.map(\.id), ["current"])
        store.stop()
    }

    func testReminderAccessIsExplicitAndPassesListSelection() {
        let provider = FakeScheduleProvider(
            authorization: .denied, reminderAuthorization: .notDetermined)
        let store = ScheduleStore(
            selectedReminderListIDs: ["tasks"],
            includeReminders: true,
            provider: provider)

        store.start()
        XCTAssertEqual(provider.reminderRequestCount, 0)
        XCTAssertEqual(provider.fetchCount, 0)

        store.requestReminderAccess()

        XCTAssertEqual(provider.reminderRequestCount, 1)
        XCTAssertEqual(provider.lastSelectedReminderListIDs, ["tasks"])
        XCTAssertTrue(provider.lastIncludeReminders)
        XCTAssertEqual(store.reminders.map(\.id), ["due"])
        store.stop()
    }

    func testSettingsModelKeepsOneAvailableCalendarSelected() {
        let model = makeSettingsModel()
        let identifiers = ["work", "personal"]

        model.setScheduleCalendar("work", enabled: false, availableIDs: identifiers)
        model.setScheduleCalendar("personal", enabled: false, availableIDs: identifiers)

        XCTAssertEqual(model.values.schedule.calendarIDs, ["personal"])
        XCTAssertFalse(model.isScheduleCalendarEnabled("work", availableIDs: identifiers))
        XCTAssertTrue(model.isScheduleCalendarEnabled("personal", availableIDs: identifiers))
    }

    func testSettingsModelKeepsOneAvailableReminderListSelected() {
        let model = makeSettingsModel()
        let identifiers = ["tasks", "home"]

        model.setScheduleReminderList("tasks", enabled: false, availableIDs: identifiers)
        model.setScheduleReminderList("home", enabled: false, availableIDs: identifiers)

        XCTAssertEqual(model.values.schedule.reminderListIDs, ["home"])
        XCTAssertFalse(
            model.isScheduleReminderListEnabled("tasks", availableIDs: identifiers))
        XCTAssertTrue(
            model.isScheduleReminderListEnabled("home", availableIDs: identifiers))
    }

    func testPanelRendersCurrentEventAtCompactSize() throws {
        let provider = FakeScheduleProvider(authorization: .granted)
        let store = ScheduleStore(provider: provider)
        store.start()
        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: SchedulePanelView(store: store, theme: Theme.theme(id: "")))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        store.stop()
    }

    func testPanelRendersReminderAtCompactSize() throws {
        let provider = FakeScheduleProvider(
            authorization: .denied,
            reminderAuthorization: .granted,
            showsEvent: false)
        let store = ScheduleStore(includeReminders: true, provider: provider)
        store.start()
        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: SchedulePanelView(store: store, theme: Theme.theme(id: "")))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        store.stop()
    }

    func testSettingsRenderGrantedCalendarList() throws {
        let provider = FakeScheduleProvider(authorization: .granted)
        let store = ScheduleStore(provider: provider)
        store.start()
        var values = makeSettingsValues()
        values.deckConfiguration.setEnabled(true, for: .schedule)
        let view = SettingsPanelView(
            selectedPane: .schedule,
            values: values,
            fontNames: ["Menlo"],
            scheduleStore: store)
        view.frame = NSRect(origin: .zero, size: SettingsPanelView.preferredSize)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertEqual(view.frame.size, SettingsPanelView.preferredSize)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        store.stop()
    }

    private func event(
        id: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false
    ) -> ScheduleEventItem {
        ScheduleEventItem(
            id: id,
            title: "Planning",
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            calendarTitle: "Work")
    }

    private func reminder(id: String, due: Date) -> ScheduleReminderItem {
        ScheduleReminderItem(
            id: id, title: "Submit report", dueDate: due,
            isAllDay: false, listTitle: "Tasks")
    }

    private func makeSettingsModel() -> SettingsPanelModel {
        SettingsPanelModel(
            selectedPane: .schedule,
            values: makeSettingsValues(),
            fontNames: ["Menlo"])
    }

    private func makeSettingsValues() -> SettingsPanelValues {
        SettingsPanelValues(
            deckConfiguration: .legacy(order: .terminalLeft, enabledPanels: .all),
            notifications: DockNotificationSettings(),
            terminal: TerminalSettingsState(
                focusWidthMultiplier: 2, focusHeightMultiplier: 4, fontName: "Menlo"),
            usage: UsageSettingsState(
                enabledProviders: UsageProviderID.allCases,
                claudeRefreshMode: .automatic,
                fontName: "Menlo", fontSize: 10,
                displayMode: .remaining, textColor: .theme, showsPace: true),
            systemStats: SystemStatsSettingsState(
                refreshInterval: 2, metrics: SystemStatsMetric.defaultSelection),
            serviceMonitor: ServiceMonitorSettingsState(
                endpoints: [], refreshInterval: 30),
            weather: WeatherSettingsState(
                location: nil, temperatureUnit: .celsius, refreshInterval: 1_800),
            schedule: ScheduleSettingsState(
                calendarIDs: [], reminderListIDs: [], includeAllDay: false,
                includeReminders: false, refreshInterval: 300),
            clock: ClockSettingsState(
                timeZoneIdentifier: ClockTimeZone.systemIdentifier, hourFormat: .system),
            battery: BatterySettingsState(refreshInterval: 60),
            network: NetworkSettingsState(refreshInterval: 2),
            projectPulse: ProjectPulseConfiguration(),
            githubInbox: GitHubInboxConfiguration(),
            docker: DockerConfiguration(),
            customTile: CustomTileConfiguration(),
            focusTimer: FocusTimerSettings(),
            appearance: AppearanceSettingsState(cornerRadius: 10, tintOpacity: 0.6))
    }
}

private final class FakeScheduleProvider: ScheduleEventProviding {
    var authorizationState: ScheduleAuthorizationState
    var reminderAuthorizationState: ScheduleAuthorizationState
    var onStoreChanged: (() -> Void)?
    private(set) var requestCount = 0
    private(set) var reminderRequestCount = 0
    private(set) var fetchCount = 0
    private(set) var suspendCount = 0
    private(set) var lastSelectedCalendarIDs: Set<String> = []
    private(set) var lastSelectedReminderListIDs: Set<String> = []
    private(set) var lastIncludeAllDay = false
    private(set) var lastIncludeReminders = false
    private let showsEvent: Bool

    init(
        authorization: ScheduleAuthorizationState,
        reminderAuthorization: ScheduleAuthorizationState = .denied,
        showsEvent: Bool = true
    ) {
        authorizationState = authorization
        reminderAuthorizationState = reminderAuthorization
        self.showsEvent = showsEvent
    }

    func requestReminderAccess(completion: @escaping (ScheduleAuthorizationState) -> Void) {
        reminderRequestCount += 1
        reminderAuthorizationState = .granted
        completion(.granted)
    }

    func requestAccess(completion: @escaping (ScheduleAuthorizationState) -> Void) {
        requestCount += 1
        authorizationState = .granted
        completion(.granted)
    }

    func suspend() { suspendCount += 1 }

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
        fetchCount += 1
        lastSelectedCalendarIDs = selectedCalendarIDs
        lastSelectedReminderListIDs = selectedReminderListIDs
        lastIncludeAllDay = includeAllDay
        lastIncludeReminders = includeReminders
        let now = Date()
        completion(
            ScheduleFetchResult(
                calendars: [
                    ScheduleCalendarSource(id: "work", title: "Work"),
                    ScheduleCalendarSource(id: "personal", title: "Personal"),
                ],
                events: showsEvent ? [
                    ScheduleEventItem(
                        id: "current", title: "Planning",
                        startDate: now.addingTimeInterval(-600),
                        endDate: now.addingTimeInterval(600),
                        isAllDay: false, calendarTitle: "Work")
                ] : [],
                reminderLists: includeReminders
                    ? [ScheduleReminderListSource(id: "tasks", title: "Tasks")] : [],
                reminders: includeReminders
                    ? [
                        ScheduleReminderItem(
                            id: "due", title: "Submit report",
                            dueDate: now.addingTimeInterval(-60),
                            isAllDay: false, listTitle: "Tasks")
                    ] : []))
    }
}
