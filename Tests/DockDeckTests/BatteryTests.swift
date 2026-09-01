import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class BatteryTests: XCTestCase {
    func testPercentUsesReportedMaximumAndClamps() {
        XCTAssertEqual(BatteryCalculator.percent(current: 48, maximum: 60), 80)
        XCTAssertEqual(BatteryCalculator.percent(current: 75, maximum: 60), 100)
        XCTAssertNil(BatteryCalculator.percent(current: 0, maximum: 0))
        XCTAssertNil(BatteryCalculator.percent(current: -1, maximum: 100))
    }

    func testTimeEstimateRejectsUnknownValues() {
        XCTAssertEqual(BatteryCalculator.minutesRemaining(95), 95)
        XCTAssertNil(BatteryCalculator.minutesRemaining(0))
        XCTAssertNil(BatteryCalculator.minutesRemaining(-1))
        XCTAssertNil(BatteryCalculator.minutesRemaining(20_000))
        XCTAssertNil(BatteryCalculator.minutesRemaining(nil))
    }

    func testReaderReturnsPlausibleInternalBatteryWhenAvailable() {
        guard let snapshot = BatteryReader.read() else { return }
        XCTAssertGreaterThanOrEqual(snapshot.percent, 0)
        XCTAssertLessThanOrEqual(snapshot.percent, 100)
        if let minutes = snapshot.minutesRemaining {
            XCTAssertGreaterThan(minutes, 0)
        }
    }

    func testPanelRendersAtCompactSize() throws {
        let store = BatteryStore(
            refreshInterval: 60,
            initialSnapshot: BatterySnapshot(
                percent: 72, state: .discharging, minutesRemaining: 215))
        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: BatteryPanelView(store: store, theme: Theme.theme(id: "")))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
}
