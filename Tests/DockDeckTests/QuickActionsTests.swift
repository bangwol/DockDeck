import XCTest
@testable import DockDeck

final class QuickActionsTests: XCTestCase {
    func testQuickActionTargetsRejectCommandsCredentialsAndBrokenPaths() throws {
        for (kind, target) in [(QuickAction.Kind.app, "/Applications/Calendar.app"), (.folder, "/tmp/work folder"),
            (.webpage, "https://example.com/path"), (.shortcut, "Work mode")] {
            XCTAssertNoThrow(try QuickAction(name: "Open", kind: kind, target: target).validated())
        }
        for (kind, target) in [(QuickAction.Kind.app, "/tmp/script.sh"), (.folder, "relative"),
            (.folder, "/" + String(repeating: "a", count: Int(PATH_MAX))),
            (.webpage, "file:///tmp/file"), (.webpage, "https://user:secret@example.com"),
            (.webpage, "https://example.com:0"), (.webpage, "javascript:alert(1)"),
            (.shortcut, "--help"), (.shortcut, "bad\nname")] {
            XCTAssertThrowsError(try QuickAction(name: "Open", kind: kind, target: target).validated())
        }
        let action = QuickAction(name: "Open", kind: .webpage, target: "https://example.com")
        XCTAssertThrowsError(try QuickAction.validated([action, action]))
        XCTAssertThrowsError(try QuickAction.validated((0..<5).map { QuickAction(name: String($0), kind: .shortcut, target: "Work") }))
    }

    func testSavingNeverRunsAndCorruptDataRequiresExplicitClear() throws {
        let suite = "DockDeckTests.actions." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let action = QuickAction(name: "Missing", kind: .app, target: "/missing/App.app")
        let store = QuickActionStore(defaults: defaults)
        try store.save([action])
        XCTAssertEqual(QuickActionStore(defaults: defaults).actions, [action])
        XCTAssertTrue(store.running.isEmpty)
        XCTAssertNil(store.error)
        defaults.set("broken", forKey: QuickActionStore.preferenceKey)
        let corrupt = QuickActionStore(defaults: defaults)
        XCTAssertThrowsError(try corrupt.save([action]))
        XCTAssertEqual(defaults.string(forKey: QuickActionStore.preferenceKey), "broken")
        corrupt.clear()
        XCTAssertNoThrow(try corrupt.save([action]))
    }

    func testLaunchDebounceUsesMonotonicTimeAndInFlightState() {
        XCTAssertTrue(QuickActionLaunchPolicy.allows(now: 1, last: nil, running: false))
        XCTAssertFalse(QuickActionLaunchPolicy.allows(now: 1.2, last: 1, running: false))
        XCTAssertTrue(QuickActionLaunchPolicy.allows(now: 2, last: 1, running: false))
        XCTAssertFalse(QuickActionLaunchPolicy.allows(now: 2, last: 1, running: true))
        for value in [Double.nan, .infinity, -1, 0.5] {
            XCTAssertFalse(QuickActionLaunchPolicy.allows(now: value, last: 1, running: false))
        }
    }
}
