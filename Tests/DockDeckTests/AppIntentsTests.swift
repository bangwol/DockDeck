import AppKit
import XCTest
@testable import DockDeck

final class AppIntentsTests: XCTestCase {
    @MainActor func testIntentsDispatchToTheAppDelegate() async throws {
        let app = NSApplication.shared
        let previous = app.delegate
        let handler = IntentTestDelegate()
        app.delegate = handler
        defer { app.delegate = previous }
        _ = try await RefreshDockDeckIntent().perform()
        _ = try await StartDockDeckFocusIntent().perform()
        let profile = SwitchDockDeckProfileIntent()
        profile.profileName = " Work "
        _ = try await profile.perform()
        XCTAssertEqual(handler.commands, [.refresh, .startFocus, .switchProfile("Work")])
    }

    func testProfileIntentRejectsInvalidNames() {
        for name in ["", " ", "Work\nOther", String(repeating: "x", count: 49)] {
            XCTAssertThrowsError(try DockDeckIntentCommand.switchProfile(name).validated())
        }
    }

    func testStartFocusIsIdempotentAndPreservesPausedTime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = FocusTimerStore(now: now)
        store.startFocus(now: now)
        XCTAssertEqual(store.snapshot.mode, .running)
        let remaining = store.snapshot.remainingSeconds
        store.startFocus(now: now.addingTimeInterval(60))
        XCTAssertEqual(store.snapshot.remainingSeconds, remaining - 60)
        store.toggle(now: now.addingTimeInterval(60))
        XCTAssertEqual(store.snapshot.mode, .paused)
        store.startFocus(now: now.addingTimeInterval(120))
        XCTAssertEqual(store.snapshot.remainingSeconds, remaining - 60)
        store.skip(now: now.addingTimeInterval(120))
        XCTAssertEqual(store.snapshot.phase, .breakTime)
        store.startFocus(now: now.addingTimeInterval(120))
        XCTAssertEqual(store.snapshot.phase, .focus)
        XCTAssertEqual(store.snapshot.mode, .running)
        store.stop()
    }
}

@MainActor private final class IntentTestDelegate: NSObject, NSApplicationDelegate, DockDeckIntentHandling {
    var commands: [DockDeckIntentCommand] = []
    func performDockDeckCommand(_ command: DockDeckIntentCommand) throws { commands.append(command) }
}
