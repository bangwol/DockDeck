import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class ClockTests: XCTestCase {
    func testExplicitHourFormatsAreStable() throws {
        let date = Date(timeIntervalSince1970: 1_704_110_640)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        XCTAssertEqual(
            ClockTextFormatter.time(date, timeZone: timeZone, format: .twentyFourHour),
            "12:04")
        XCTAssertEqual(
            ClockTextFormatter.time(date, timeZone: timeZone, format: .twelveHour),
            "12:04 PM")
    }

    func testInvalidTimeZoneFallsBackToSystem() {
        XCTAssertEqual(
            ClockTimeZone.normalized(identifier: "not/a-time-zone"),
            ClockTimeZone.systemIdentifier)
        XCTAssertEqual(
            ClockTimeZone.normalized(identifier: "Asia/Seoul"),
            "Asia/Seoul")
    }

    func testPanelRendersAtCompactSize() throws {
        let store = ClockStore(now: Date(timeIntervalSince1970: 1_704_110_640))
        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: ClockPanelView(
                store: store,
                theme: Theme.theme(id: ""),
                timeZoneIdentifier: "Asia/Seoul",
                hourFormat: .twentyFourHour))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
}
