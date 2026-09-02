import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class FocusTimerTests: XCTestCase {
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
