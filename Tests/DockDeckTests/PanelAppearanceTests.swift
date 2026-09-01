import Cocoa
import XCTest

@testable import DockDeck

final class PanelAppearanceTests: XCTestCase {
    func testEnabledPanelsKeepsSingleSelectionsAndRecoversEmptyState() {
        XCTAssertEqual(EnabledPanels.resolved(.terminal), .terminal)
        XCTAssertEqual(EnabledPanels.resolved(.usage), .usage)
        XCTAssertEqual(EnabledPanels.resolved([]), .all)
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
