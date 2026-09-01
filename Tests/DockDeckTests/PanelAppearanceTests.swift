import Cocoa
import XCTest

@testable import DockDeck

final class PanelAppearanceTests: XCTestCase {
    func testEnabledPanelsKeepsSingleSelectionsAndRecoversEmptyState() {
        XCTAssertEqual(EnabledPanels.resolved(.terminal), .terminal)
        XCTAssertEqual(EnabledPanels.resolved(.usage), .usage)
        XCTAssertEqual(EnabledPanels.resolved([]), .all)
    }

    func testDeckConfigurationAdaptsExistingPlacementAndVisibility() {
        let configuration = PanelDeckConfiguration.legacy(
            order: .terminalRight, enabledPanels: .terminal)

        XCTAssertEqual(configuration.left, [.usage])
        XCTAssertEqual(configuration.right, [.terminal])
        XCTAssertEqual(configuration.enabled, [.terminal])
        XCTAssertEqual(configuration.side(containing: .terminal), .right)
    }

    func testDeckConfigurationKeepsFutureModulesWhileRemovingDuplicates() throws {
        let clock = PanelModuleID(rawValue: "clock")
        let configuration = PanelDeckConfiguration(
            left: [.terminal, clock, .terminal],
            right: [.usage, clock],
            enabled: [clock, clock]
        ).normalized()
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(PanelDeckConfiguration.self, from: data)

        XCTAssertEqual(decoded.left, [.terminal, clock])
        XCTAssertEqual(decoded.right, [.usage])
        XCTAssertEqual(decoded.enabled, [clock])
    }

    func testShellRestartPolicyStopsARepeatedExitLoop() {
        var policy = ShellRestartPolicy()
        let start = Date(timeIntervalSince1970: 100)

        policy.recordStart(at: start)
        XCTAssertTrue(policy.shouldRestart(afterExitAt: start.addingTimeInterval(3)))
        for offset in 4...5 {
            let nextStart = start.addingTimeInterval(TimeInterval(offset))
            policy.recordStart(at: nextStart)
            XCTAssertTrue(
                policy.shouldRestart(afterExitAt: nextStart.addingTimeInterval(0.5)))
        }
        let finalStart = start.addingTimeInterval(6)
        policy.recordStart(at: finalStart)
        XCTAssertFalse(
            policy.shouldRestart(afterExitAt: finalStart.addingTimeInterval(0.5)))
    }

    func testReadableTerminalUsesStrongerTintThanCompactPanels() {
        let compact = PanelAppearance.tintOpacity(base: 0.65, presentation: .compact)
        let readable = PanelAppearance.tintOpacity(base: 0.65, presentation: .readable)

        XCTAssertEqual(compact, 0.247, accuracy: 0.001)
        XCTAssertEqual(readable, 0.82, accuracy: 0.001)
        XCTAssertGreaterThan(readable, compact)
    }

    func testUsagePanelAcceptsContextMenuWithoutTakingKeyboardFocus() throws {
        let controller = QuotaPanelController(
            initialFrame: NSRect(x: 0, y: 0, width: 214, height: 59),
            theme: Theme.theme(id: ""), store: UsageStore(), menuTarget: NSObject())
        let menu = try XCTUnwrap(controller.panel.contentView?.menu)

        controller.menuWillOpen(menu)

        XCTAssertFalse(controller.panel.ignoresMouseEvents)
        XCTAssertFalse(controller.panel.canBecomeKey)
        XCTAssertEqual(
            menu.items.filter { !$0.isSeparatorItem }.map(\.title),
            [
                "Settings…", "Show Used Values", "Move Terminal to Right",
                "Refresh Usage & Layout",
            ])
    }
}
