import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class SystemStatsTests: XCTestCase {
    func testMetricSelectionUsesStableTwoToFourTileBounds() {
        XCTAssertEqual(SystemStatsMetric.normalized([]), [.cpu, .memory, .disk, .network])
        XCTAssertEqual(SystemStatsMetric.normalized([.thermal]), [.cpu, .thermal])
        XCTAssertEqual(
            SystemStatsMetric.normalized(SystemStatsMetric.allCases),
            [.cpu, .memory, .disk, .network])
        XCTAssertEqual(
            SystemStatsMetric.normalized([.thermal, .network, .network]),
            [.network, .thermal])
    }

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

    func testMemoryUsedExcludesInactiveFileCache() {
        XCTAssertEqual(
            SystemStatsCalculator.activityMonitorMemoryUsedPages(
                internalPages: 600, wiredPages: 100, compressorPages: 50),
            750)
    }

    func testSMCTemperatureParserUsesHottestCPUCoreForChipGeneration() {
        let output = """
            [INFO] found
            [TC0P] 54.5
            [Tp00] 57.25
            [Tp0C] 61.25
            [Tf16] 95.0
            [TG0B] 0.0
            [TBAD] 130.0
            """

        XCTAssertEqual(
            SMCTemperatureOutputParser.hottestCPUCelsius(
                from: output, chipGeneration: 5),
            61.25)
    }

    func testInstalledTemperatureReaderReturnsPlausibleValueWhenAvailable() throws {
        guard InstalledTemperatureReader.isAvailable else {
            throw XCTSkip("Signed Stats SMC tool is not installed")
        }
        let value = try XCTUnwrap(InstalledTemperatureReader.readHottestCPUCelsius())
        XCTAssertTrue((5...125).contains(value))
    }

    func testStoreReadsLocalMemoryAndDiskMetrics() {
        let store = SystemStatsStore(
            refreshInterval: 10, metrics: [.cpu, .memory, .disk])

        store.start()
        defer { store.stop() }

        XCTAssertNotNil(store.snapshot.memoryPercent)
        XCTAssertNotNil(store.snapshot.diskPercent)
    }

    func testPanelRendersAtCompactSize() throws {
        let store = SystemStatsStore(
            metrics: [.cpu, .memory, .network, .thermal],
            initialSnapshot: SystemStatsSnapshot(
                cpuPercent: 18,
                memoryPercent: 64,
                downloadBytesPerSecond: 1_572_864,
                uploadBytesPerSecond: 131_072,
                temperatureCelsius: 57.5,
                thermalPressure: .fair))
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
