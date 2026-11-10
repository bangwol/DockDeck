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

    func testAsymmetricSidesUseTheirOwnAvailableWidth() {
        let host = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let tray = NSRect(x: 180, y: 0, width: 590, height: 64)

        let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)

        XCTAssertEqual(frames.terminal, NSRect(x: 0, y: -5, width: 176, height: 64))
        XCTAssertEqual(frames.quota, NSRect(x: 774, y: -5, width: 226, height: 64))
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

    func testNarrowSidesFoldWithoutOverlappingDock() {
        let host = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let tray = NSRect(x: 150, y: 0, width: 714, height: 64)

        let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)

        XCTAssertEqual(frames.leftMode, .capsule)
        XCTAssertEqual(frames.rightMode, .capsule)
        XCTAssertEqual(frames.terminal, NSRect(x: 0, y: -5, width: 84, height: 36))
        XCTAssertEqual(frames.quota, NSRect(x: 916, y: -5, width: 84, height: 36))
    }

    func testFoldThresholdsShrinkImmediatelyAndRequireRoomToExpand() {
        let cases: [(CGFloat, DockPanelMode)] = [
            (160, .full), (159, .capsule), (84, .capsule), (83, .tab), (28, .tab), (0, .tab),
        ]
        for (width, mode) in cases {
            XCTAssertEqual(DockPanelMode.resolved(availableWidth: width), mode)
        }
        XCTAssertEqual(DockPanelMode.resolved(availableWidth: 159, previous: .full), .capsule)
        XCTAssertEqual(DockPanelMode.resolved(availableWidth: 171, previous: .capsule), .capsule)
        XCTAssertEqual(DockPanelMode.resolved(availableWidth: 172, previous: .capsule), .full)
        XCTAssertEqual(DockPanelMode.resolved(availableWidth: 83, previous: .capsule), .tab)
        XCTAssertEqual(DockPanelMode.resolved(availableWidth: 95, previous: .tab), .tab)
        XCTAssertEqual(DockPanelMode.resolved(availableWidth: 96, previous: .tab), .capsule)
        XCTAssertEqual(DockPanelMode.resolved(availableWidth: 172, previous: .tab), .full)
    }

    func testOnlyCrowdedSideFoldsAndVeryCrowdedTabMovesAboveDock() throws {
        let host = NSRect(x: -1000, y: 100, width: 1000, height: 700)
        let cases: [(CGFloat, DockPanelMode)] = [
            (200, .full), (120, .capsule), (40, .tab), (10, .tab),
        ]
        for (leftSpace, expected) in cases {
            let tray = NSRect(x: host.minX + leftSpace + DockPanelLayout.gap,
                              y: 110, width: 500, height: 90)
            let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)
            let left = try XCTUnwrap(frames.terminal)
            let right = try XCTUnwrap(frames.quota)
            XCTAssertEqual(frames.leftMode, expected)
            XCTAssertEqual(frames.rightMode, .full)
            XCTAssertTrue(host.contains(left))
            XCTAssertTrue(host.contains(right))
            XCTAssertFalse(left.intersects(tray))
            XCTAssertFalse(right.intersects(tray))
            if leftSpace < DockPanelMode.tab.minimumWidth {
                XCTAssertEqual(left.minY, tray.maxY + DockPanelLayout.gap)
            }
        }
    }

    func testNoTabIsPlacedOverDockWhenThereIsNoVerticalRoomEither() {
        let host = NSRect(x: 0, y: 0, width: 300, height: 100)
        let tray = NSRect(x: 0, y: 0, width: 300, height: 100)
        let frames = DockPanelLayout.frames(tray: tray, hostFrame: host)
        XCTAssertNil(frames.terminal)
        XCTAssertNil(frames.quota)
    }

    func testLayoutCarriesHysteresisIndependentlyForEachSide() {
        let host = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let previous = DockPanelFrames(terminal: nil, quota: nil, leftMode: .tab, rightMode: .full)
        let frames = DockPanelLayout.frames(
            tray: NSRect(x: 96, y: 10, width: 700, height: 64),
            hostFrame: host, previous: previous)
        XCTAssertEqual(frames.leftMode, .tab)
        XCTAssertEqual(frames.rightMode, .full)
    }

    func testHiddenTerminalAnchorKeepsSizeAndMovesToNewScreenEdge() {
        let host = NSRect(x: -1440, y: 200, width: 1440, height: 900)
        let size = NSSize(width: 214, height: 59)
        let anchor = DockPanelLayout.terminalAnchor(
            on: .right, hostFrame: host, bottom: 205, previousSize: size)
        XCTAssertEqual(anchor, NSRect(x: -214, y: 205, width: 214, height: 59))
        XCTAssertTrue(host.contains(anchor))
    }

    func testHoverTrackingUsesEachScreensBottomInsteadOfGlobalOrigin() {
        let screens = [NSRect(x: -1440, y: 200, width: 1440, height: 900)]
        XCTAssertTrue(DockHoverTracking.isNearDock(pointer: NSPoint(x: -500, y: 210), screens: screens))
        XCTAssertFalse(DockHoverTracking.isNearDock(pointer: NSPoint(x: -500, y: 500), screens: screens))
        XCTAssertFalse(DockHoverTracking.isNearDock(pointer: NSPoint(x: 500, y: 210), screens: screens))
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
