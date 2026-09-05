import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class SystemStatsTests: XCTestCase {
    func testMeasureNativeSamplingAndBoundedHistoryWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["DOCKDECK_MEASURE_METRICS"] == "1" else {
            throw XCTSkip("Set DOCKDECK_MEASURE_METRICS=1 to measure local sampling")
        }
        let start = Date()
        for _ in 0..<100 { _ = NetworkCounterReader.read() }
        let networkDuration = Date().timeIntervalSince(start)
        var history = MetricHistory()
        let historyStart = Date()
        for index in 0..<10_000 {
            history.append(Double(index % 100), at: start.addingTimeInterval(Double(index)))
        }
        let historyDuration = Date().timeIntervalSince(historyStart)
        XCTAssertEqual(history.samples.count, MetricHistory.maximumSampleCount)
        let view = NSHostingView(rootView: MetricSparkline(samples: history.samples, color: .cyan))
        view.frame = NSRect(x: 0, y: 0, width: 250, height: 40)
        let renderStart = Date()
        for _ in 0..<100 {
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        print("Metric benchmark: network read ms=\(networkDuration * 10); history append ms=\(historyDuration / 10); 900-point render ms=\(Date().timeIntervalSince(renderStart) * 10)")
    }

    func testMetricHistoryCalculatesInterpolatedPercentiles() {
        var history = MetricHistory()
        for value in [10.0, 40.0, 20.0, 30.0] { history.append(value) }

        XCTAssertEqual(history.percentile(0), 10)
        XCTAssertEqual(history.percentile(0.5), 25)
        XCTAssertEqual(history.percentile(0.95), 38.5)
        XCTAssertEqual(history.percentile(1), 40)
    }

    func testMetricHistoryPrunesOldSamplesAndBoundsMemory() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        var history = MetricHistory()
        history.append(1, at: now.addingTimeInterval(-901))
        for offset in 0...MetricHistory.maximumSampleCount {
            history.append(Double(offset), at: now.addingTimeInterval(Double(offset) / 10))
        }

        XCTAssertEqual(history.samples.count, MetricHistory.maximumSampleCount)
        XCTAssertEqual(history.samples.first?.value, 1)
        XCTAssertEqual(history.samples.last?.value, Double(MetricHistory.maximumSampleCount))
        XCTAssertFalse(history.samples.contains { $0.timestamp < now.addingTimeInterval(-900) })
    }

    func testMetricHistoryRejectsInvalidValuesAndResetsOnClockRollback() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        var history = MetricHistory()
        history.append(10, at: now)
        history.append(.infinity, at: now.addingTimeInterval(1))
        history.append(-1, at: now.addingTimeInterval(2))
        history.append(20, at: now.addingTimeInterval(-1))

        XCTAssertEqual(history.samples, [MetricSample(
            timestamp: now.addingTimeInterval(-1), value: 20)])
    }

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
