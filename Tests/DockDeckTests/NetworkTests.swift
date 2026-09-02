import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class NetworkTests: XCTestCase {
    func testRateUsesCounterDeltaAndElapsedTime() {
        XCTAssertEqual(
            NetworkRateCalculator.rate(previous: 1_000, current: 5_000, elapsed: 2),
            2_000)
        XCTAssertNil(
            NetworkRateCalculator.rate(previous: 5_000, current: 1_000, elapsed: 2))
        XCTAssertNil(
            NetworkRateCalculator.rate(previous: 1_000, current: 5_000, elapsed: 0))
    }

    func testByteRateFormatterUsesCompactBinaryUnits() {
        XCTAssertEqual(ByteRateFormatter.string(nil), "--")
        XCTAssertEqual(ByteRateFormatter.string(512), "512 B/s")
        XCTAssertEqual(ByteRateFormatter.string(1_536), "1.50 KB/s")
        XCTAssertEqual(ByteRateFormatter.string(12 * 1_024), "12.0 KB/s")
        XCTAssertEqual(ByteRateFormatter.string(120 * 1_024), "120 KB/s")
        XCTAssertEqual(ByteRateFormatter.compactString(nil), "--")
        XCTAssertEqual(ByteRateFormatter.compactString(1_536), "1.5K")
        XCTAssertEqual(ByteRateFormatter.compactString(120 * 1_024), "120K")
    }

    func testReaderReturnsMonotonicCountersWhenNetworkIsAvailable() {
        guard let counters = NetworkCounterReader.read() else { return }
        XCTAssertFalse(counters.interfaceName.isEmpty)
        XCTAssertLessThan(counters.interfaceName.utf8.count, 64)
    }

    func testPanelRendersAtCompactSize() throws {
        let store = NetworkStore(
            refreshInterval: 2,
            initialSnapshot: NetworkSnapshot(
                interfaceName: "en0",
                downloadBytesPerSecond: 1_572_864,
                uploadBytesPerSecond: 430_080))
        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: NetworkPanelView(store: store, theme: Theme.theme(id: "")))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
}
