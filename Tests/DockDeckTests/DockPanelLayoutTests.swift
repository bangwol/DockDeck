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

    func testAsymmetricSidesUseMatchingSmallerWidth() {
        let host = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let tray = NSRect(x: 180, y: 0, width: 590, height: 64)

        let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)

        XCTAssertEqual(frames.terminal, NSRect(x: 0, y: -5, width: 176, height: 64))
        XCTAssertEqual(frames.quota, NSRect(x: 824, y: -5, width: 176, height: 64))
    }

    func testCompactPanelsFitCurrentScreenGeometry() {
        let host = NSRect(x: 0, y: 0, width: 1800, height: 1169)
        let tray = NSRect(x: 218, y: 10, width: 1364, height: 59)

        let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)

        XCTAssertEqual(frames.terminal?.width, 214)
        XCTAssertEqual(frames.quota?.width, 214)
        XCTAssertEqual(frames.terminal?.minY, 5)
        XCTAssertEqual(frames.terminal?.maxY, 64)
    }

    func testVeryNarrowSidesAreHiddenInsteadOfOverlappingDock() {
        let host = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let tray = NSRect(x: 150, y: 0, width: 714, height: 64)

        let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)

        XCTAssertNil(frames.terminal)
        XCTAssertNil(frames.quota)
    }

    func testFocusedTerminalGrowsTwoByFourAndStaysOnScreen() {
        let host = NSRect(x: 0, y: 0, width: 1800, height: 1169)
        let collapsed = NSRect(x: 0, y: -5, width: 214, height: 65)

        let focused = DockPanelLayout.focusedTerminalFrame(
            collapsed: collapsed, hostFrame: host)

        XCTAssertEqual(focused, NSRect(x: 0, y: 0, width: 428, height: 260))
        XCTAssertTrue(host.contains(focused))
    }

    func testFocusedTerminalIsCappedToSmallScreen() {
        let host = NSRect(x: 100, y: 50, width: 320, height: 200)
        let collapsed = NSRect(x: 100, y: 50, width: 240, height: 64)

        let focused = DockPanelLayout.focusedTerminalFrame(
            collapsed: collapsed, hostFrame: host)

        XCTAssertEqual(focused, host)
    }

    func testFocusedTerminalUsesConfiguredMultipliers() {
        let host = NSRect(x: 0, y: 0, width: 1800, height: 1169)
        let collapsed = NSRect(x: 0, y: 0, width: 214, height: 65)

        let focused = DockPanelLayout.focusedTerminalFrame(
            collapsed: collapsed, hostFrame: host,
            widthMultiplier: 3, heightMultiplier: 6)

        XCTAssertEqual(focused, NSRect(x: 0, y: 0, width: 642, height: 390))
    }

    func testFallbackPanelsUseMatchingWidths() {
        let host = NSRect(x: 0, y: 0, width: 1800, height: 1169)

        let frames = DockPanelLayout.fallbackFrames(hostFrame: host, reservedHeight: 65)

        XCTAssertEqual(frames.terminal, NSRect(x: 0, y: 5, width: 214, height: 59))
        XCTAssertEqual(frames.quota, NSRect(x: 1586, y: 5, width: 214, height: 59))
    }

    func testPanelOrderCanSwapTerminalAndUsageSlots() {
        let left = NSRect(x: 0, y: 5, width: 214, height: 59)
        let right = NSRect(x: 1586, y: 5, width: 214, height: 59)
        let frames = DockPanelFrames(terminal: left, quota: right)

        XCTAssertEqual(frames.ordered(.terminalLeft), frames)
        XCTAssertEqual(
            frames.ordered(.terminalRight),
            DockPanelFrames(terminal: right, quota: left))
    }
}
