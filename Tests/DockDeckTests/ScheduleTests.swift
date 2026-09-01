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

    func testSettingsModelKeepsOneAvailableCalendarSelected() {
        let model = makeSettingsModel()
        let identifiers = ["work", "personal"]

        model.setScheduleCalendar("work", enabled: false, availableIDs: identifiers)
        model.setScheduleCalendar("personal", enabled: false, availableIDs: identifiers)

        XCTAssertEqual(model.values.schedule.calendarIDs, ["personal"])
        XCTAssertFalse(model.isScheduleCalendarEnabled("work", availableIDs: identifiers))
        XCTAssertTrue(model.isScheduleCalendarEnabled("personal", availableIDs: identifiers))
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

    private func makeSettingsModel() -> SettingsPanelModel {
        SettingsPanelModel(
            selectedPane: .schedule,
            values: makeSettingsValues(),
            fontNames: ["Menlo"])
    }

    private func makeSettingsValues() -> SettingsPanelValues {
        SettingsPanelValues(
            deckConfiguration: .legacy(order: .terminalLeft, enabledPanels: .all),
            terminal: TerminalSettingsState(
                focusWidthMultiplier: 2, focusHeightMultiplier: 4, fontName: "Menlo"),
            usage: UsageSettingsState(
                enabledProviders: UsageProviderID.allCases,
                fontName: "Menlo", fontSize: 10,
                displayMode: .remaining, textColor: .theme),
            systemStats: SystemStatsSettingsState(refreshInterval: 2),
            serviceMonitor: ServiceMonitorSettingsState(
                endpoints: [], refreshInterval: 30),
            weather: WeatherSettingsState(
                location: nil, temperatureUnit: .celsius, refreshInterval: 1_800),
            schedule: ScheduleSettingsState(
                calendarIDs: [], includeAllDay: false, refreshInterval: 300),
            clock: ClockSettingsState(
                timeZoneIdentifier: ClockTimeZone.systemIdentifier, hourFormat: .system),
            battery: BatterySettingsState(refreshInterval: 60),
            network: NetworkSettingsState(refreshInterval: 2),
            appearance: AppearanceSettingsState(cornerRadius: 10, tintOpacity: 0.6))
    }
}

private final class FakeScheduleProvider: ScheduleEventProviding {
    var authorizationState: ScheduleAuthorizationState
    var onStoreChanged: (() -> Void)?
    private(set) var requestCount = 0
    private(set) var fetchCount = 0
    private(set) var suspendCount = 0
    private(set) var lastSelectedCalendarIDs: Set<String> = []
    private(set) var lastIncludeAllDay = false

    init(authorization: ScheduleAuthorizationState) {
        authorizationState = authorization
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
        selectedCalendarIDs: Set<String>,
        includeAllDay: Bool,
        completion: @escaping (ScheduleFetchResult) -> Void
    ) {
        fetchCount += 1
        lastSelectedCalendarIDs = selectedCalendarIDs
        lastIncludeAllDay = includeAllDay
        let now = Date()
        completion(
            ScheduleFetchResult(
                calendars: [
                    ScheduleCalendarSource(id: "work", title: "Work"),
                    ScheduleCalendarSource(id: "personal", title: "Personal"),
                ],
                events: [
                    ScheduleEventItem(
                        id: "current", title: "Planning",
                        startDate: now.addingTimeInterval(-600),
                        endDate: now.addingTimeInterval(600),
                        isAllDay: false, calendarTitle: "Work")
                ]))
    }
}
