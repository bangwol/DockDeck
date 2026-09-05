import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class FocusTimerTests: XCTestCase {
    func testCompletionBoundsCorruptRestoredCounts() {
        let now = Date(timeIntervalSince1970: 1000)
        for (count, expected) in [(Int.min, 1), (Int.max, FocusTimerSession.maximumCompletedFocusCount)] {
            let session = FocusTimerSession(phase: .focus, mode: .running,
                deadline: now, remainingSeconds: 1500, totalSeconds: 1500, completedFocusCount: count)
            let store = FocusTimerStore(session: session, now: now)
            store.refresh(now: now)
            XCTAssertEqual(store.completedFocusCount, expected)
        }
    }

    func testOlderSettingsAndSessionsRetainDefaults() throws {
        let settings = try JSONDecoder().decode(FocusTimerSettings.self,
            from: Data(#"{"focusMinutes":45,"breakMinutes":10}"#.utf8))
        XCTAssertFalse(settings.automaticallyAdvances)
        let session = try JSONDecoder().decode(FocusTimerSession.self,
            from: Data(#"{"phase":"focus","mode":"idle","remainingSeconds":1500,"totalSeconds":1500}"#.utf8))
        XCTAssertEqual(session.completedFocusCount, 0)
    }

    func testAutomaticAdvanceCountsOnceAfterLongSleepAndPersistsTogether() throws {
        var settings = FocusTimerSettings()
        settings.automaticallyAdvances = true
        let now = Date(timeIntervalSince1970: 1000)
        var saved: FocusTimerSession?
        let store = FocusTimerStore(settings: settings, now: now, onSessionChange: { saved = $0 })
        store.toggle(now: now)
        let wake = now.addingTimeInterval(30 * 24 * 3600)
        store.refresh(now: wake)
        store.refresh(now: wake)
        XCTAssertEqual(store.completedFocusCount, 1)
        XCTAssertEqual(store.snapshot.phase, .breakTime)
        XCTAssertEqual(store.snapshot.mode, .running)
        XCTAssertEqual(store.snapshot.remainingSeconds, 300)
        let restored = try JSONDecoder().decode(FocusTimerSession.self,
            from: JSONEncoder().encode(XCTUnwrap(saved)))
        XCTAssertEqual(restored.completedFocusCount, 1)
        store.skip(now: wake)
        store.reset(now: wake)
        XCTAssertEqual(store.completedFocusCount, 1)
        store.clearCompletedCount(now: wake)
        XCTAssertEqual(store.completedFocusCount, 0)
    }

    func testSettingsNormalizeAndResolvePhaseDurations() {
        var settings = FocusTimerSettings()
        settings.focusMinutes = 42
        settings.breakMinutes = 12

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.focusMinutes, 45)
        XCTAssertEqual(normalized.breakMinutes, 10)
        XCTAssertEqual(normalized.durationSeconds(for: .focus), 45 * 60)
        XCTAssertEqual(normalized.durationSeconds(for: .breakTime), 10 * 60)
    }

    func testExtremeSettingsRestoreToSupportedDurations() throws {
        for (value, focus, pause) in [(Int.min, 15, 5), (Int.max, 60, 15)] {
            let data = Data("{\"focusMinutes\":\(value),\"breakMinutes\":\(value)}".utf8)
            let settings = try JSONDecoder().decode(FocusTimerSettings.self, from: data).normalized()
            XCTAssertEqual(settings.focusMinutes, focus)
            XCTAssertEqual(settings.breakMinutes, pause)
        }
    }

    func testExtremeDeadlineRestoresWithoutOverflow() {
        let now = Date(timeIntervalSince1970: 10_000)
        for (interval, expected) in [(Double.greatestFiniteMagnitude, 1_500),
                                     (-Double.greatestFiniteMagnitude, 0)] {
            let session = FocusTimerSession(
                phase: .focus, mode: .running,
                deadline: Date(timeIntervalSinceReferenceDate: interval),
                remainingSeconds: 1_500, totalSeconds: 1_500)
            let store = FocusTimerStore(session: session, now: now)
            XCTAssertEqual(store.snapshot.remainingSeconds, expected)
            store.toggle(now: now)
            XCTAssertLessThanOrEqual(store.snapshot.remainingSeconds, 1_500)
        }
    }

    func testCorruptPausedSessionAtZeroRestoresIdleDuration() {
        let settings = FocusTimerSettings()
        let session = FocusTimerSession(
            phase: .focus,
            mode: .paused,
            deadline: nil,
            remainingSeconds: 0,
            totalSeconds: settings.durationSeconds(for: .focus))

        let normalized = session.normalized(settings: settings)

        XCTAssertEqual(normalized.mode, .idle)
        XCTAssertEqual(normalized.remainingSeconds, 25 * 60)
        XCTAssertEqual(normalized.totalSeconds, 25 * 60)
    }

    func testTimerStartsPausesAndResumesFromDeadline() {
        let now = Date(timeIntervalSince1970: 10_000)
        var persisted: [FocusTimerSession] = []
        let store = FocusTimerStore(
            now: now,
            onSessionChange: { persisted.append($0) })

        store.toggle(now: now)
        XCTAssertEqual(store.snapshot.mode, .running)
        XCTAssertEqual(store.snapshot.timeLabel, "25:00")

        store.toggle(now: now.addingTimeInterval(61))
        XCTAssertEqual(store.snapshot.mode, .paused)
        XCTAssertEqual(store.snapshot.remainingSeconds, 1_439)

        store.toggle(now: now.addingTimeInterval(120))
        XCTAssertEqual(store.snapshot.mode, .running)
        XCTAssertEqual(store.snapshot.remainingSeconds, 1_439)
        XCTAssertEqual(persisted.count, 3)
    }

    func testCompletionMovesToNextPhaseAndPersistsOnce() {
        let now = Date(timeIntervalSince1970: 20_000)
        let settings = FocusTimerSettings()
        let session = FocusTimerSession(
            phase: .focus,
            mode: .running,
            deadline: now.addingTimeInterval(5),
            remainingSeconds: settings.durationSeconds(for: .focus),
            totalSeconds: settings.durationSeconds(for: .focus))
        var persisted: [FocusTimerSession] = []
        var completions: [FocusTimerPhase] = []
        let store = FocusTimerStore(
            settings: settings,
            session: session,
            now: now,
            onSessionChange: { persisted.append($0) },
            onCompletion: { completions.append($0) })

        store.refresh(now: now.addingTimeInterval(6))
        store.refresh(now: now.addingTimeInterval(7))

        XCTAssertEqual(completions, [.focus])
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(store.snapshot.phase, .breakTime)
        XCTAssertEqual(store.snapshot.mode, .idle)
        XCTAssertEqual(store.snapshot.timeLabel, "05:00")
    }

    func testResetAndSkipUseConfiguredDurations() {
        var settings = FocusTimerSettings()
        settings.focusMinutes = 45
        settings.breakMinutes = 10
        let store = FocusTimerStore(settings: settings)

        store.skip()
        XCTAssertEqual(store.snapshot.phase, .breakTime)
        XCTAssertEqual(store.snapshot.remainingSeconds, 10 * 60)

        store.toggle()
        store.reset()
        XCTAssertEqual(store.snapshot.mode, .idle)
        XCTAssertEqual(store.snapshot.remainingSeconds, 10 * 60)
    }

    func testPanelRendersAtCompactSize() throws {
        let store = FocusTimerStore()
        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: FocusTimerPanelView(store: store, theme: Theme.theme(id: "")))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
}
