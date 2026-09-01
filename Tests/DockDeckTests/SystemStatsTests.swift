import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class SystemStatsTests: XCTestCase {
    func testCPUPercentUsesCounterDeltas() throws {
        let previous = CPUCounters(user: 100, system: 50, idle: 850, nice: 0)
        let current = CPUCounters(user: 160, system: 90, idle: 950, nice: 0)

        let percent = try XCTUnwrap(
            SystemStatsCalculator.cpuPercent(previous: previous, current: current))

        XCTAssertEqual(percent, 50, accuracy: 0.001)
    }

    func testPercentClampsAndRejectsMissingTotal() {
        XCTAssertEqual(SystemStatsCalculator.boundedPercent(used: 125, total: 100), 100)
        XCTAssertEqual(SystemStatsCalculator.boundedPercent(used: 25, total: 100), 25)
        XCTAssertNil(SystemStatsCalculator.boundedPercent(used: 0, total: 0))
    }

    func testStoreReadsLocalMemoryAndDiskMetrics() {
        let store = SystemStatsStore(refreshInterval: 10)

        store.start()
        defer { store.stop() }

        XCTAssertNotNil(store.snapshot.memoryPercent)
        XCTAssertNotNil(store.snapshot.diskPercent)
    }

    func testPanelRendersAtCompactSize() throws {
        let store = SystemStatsStore(
            initialSnapshot: SystemStatsSnapshot(
                cpuPercent: 18, memoryPercent: 64, diskPercent: 82))
        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: SystemStatsPanelView(store: store, theme: Theme.theme(id: "")))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
}
