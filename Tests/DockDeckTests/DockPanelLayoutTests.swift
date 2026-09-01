import Cocoa
import XCTest

@testable import DockDeck

final class DockPanelLayoutTests: XCTestCase {
    func testFramesUseOnlySpaceOutsideDockTray() {
        let host = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let tray = NSRect(x: 470, y: 0, width: 500, height: 74)

        let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)

        XCTAssertEqual(frames.terminal, NSRect(x: 0, y: -5, width: 466, height: 74))
        XCTAssertEqual(frames.quota, NSRect(x: 974, y: -5, width: 466, height: 74))
        XCTAssertLessThanOrEqual(frames.terminal!.maxX, tray.minX)
        XCTAssertGreaterThanOrEqual(frames.quota!.minX, tray.maxX)
    }

    func testNarrowSideIsHiddenInsteadOfOverlappingDock() {
        let host = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let tray = NSRect(x: 180, y: 0, width: 590, height: 64)

        let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)

        XCTAssertNil(frames.terminal)
        XCTAssertEqual(frames.quota, NSRect(x: 774, y: -5, width: 226, height: 64))
    }

    func testCompactPanelsFitCurrentScreenGeometry() {
        let host = NSRect(x: 0, y: 0, width: 1800, height: 1169)
        let tray = NSRect(x: 218, y: 10, width: 1364, height: 59)

        let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)

        XCTAssertEqual(frames.terminal?.width, 214)
        XCTAssertEqual(frames.quota?.width, 214)
    }
}
