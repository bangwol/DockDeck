import Cocoa
import Combine
import SwiftUI
import XCTest

@testable import DockDeck

final class DockerTests: XCTestCase {
    func testContainerMetricsAreSortedBoundedAndIncludedInTotals() throws {
        let lines = (0..<60).map { index in
            "{\"ID\":\"id-\(index)\",\"Name\":\"worker-\(index)\",\"CPUPerc\":\"\(index)%\",\"MemUsage\":\"1MiB / 1GiB\"}"
        }.joined(separator: "\n")
        let stats = try DockerOutputParser.parseStats(Data(lines.utf8))
        XCTAssertEqual(stats.containers.count, 50)
        XCTAssertEqual(stats.containers.first?.name, "worker-59")
        XCTAssertEqual(stats.containers.last?.cpuPercent, 10)
        XCTAssertEqual(stats.memoryBytes, 60 * 1_048_576)
        XCTAssertEqual(stats.cpuPercent, Double((0..<60).reduce(0, +)))
    }

    func testConfigurationChoosesNearestRefreshInterval() {
        XCTAssertEqual(DockerConfiguration(refreshInterval: 8).refreshInterval, 10)
        XCTAssertEqual(DockerConfiguration(refreshInterval: 29).refreshInterval, 30)
    }

    func testContainerParserCountsStateAndHealth() throws {
        let data = Data(
            """
            {"State":"running","Status":"Up 2 hours (healthy)"}
            {"State":"running","Status":"Up 3 minutes (unhealthy)"}
            {"State":"exited","Status":"Exited (0) 1 hour ago"}
            """.utf8)

        let counts = try DockerOutputParser.parseContainers(data)

        XCTAssertEqual(counts.running, 2)
        XCTAssertEqual(counts.stopped, 1)
        XCTAssertEqual(counts.unhealthy, 1)
    }

    func testStatsParserSumsCPUAndMemory() throws {
        let data = Data(
            """
            {"CPUPerc":"0.25%","MemUsage":"81.5MiB / 1GiB"}
            {"CPUPerc":"1.50%","MemUsage":"1.25GiB / 2GiB"}
            """.utf8)

        let stats = try DockerOutputParser.parseStats(data)

        XCTAssertEqual(stats.cpuPercent, 1.75, accuracy: 0.001)
        XCTAssertEqual(
            stats.memoryBytes,
            81.5 * 1_048_576 + 1.25 * 1_073_741_824,
            accuracy: 1)
        XCTAssertEqual(DockerOutputParser.bytes("7.91MB"), 7_910_000)
    }

    func testStatsParserRejectsValuesThatCannotBeDisplayedSafely() {
        XCTAssertNil(DockerOutputParser.bytes("9000000000GiB"))
        XCTAssertThrowsError(try DockerOutputParser.parseStats(
            Data(#"{"CPUPerc":"1e30%","MemUsage":"1MiB / 1GiB"}"#.utf8)))
        XCTAssertThrowsError(
            try DockerOutputParser.parseStats(Data(
                """
                {"CPUPerc":"0.25%","MemUsage":"9000000000GiB / 1GiB"}
                """.utf8))
        ) { error in
            guard let error = error as? DockerError else {
                return XCTFail("Expected DockerError.invalidOutput")
            }
            guard case .invalidOutput = error else {
                return XCTFail("Expected DockerError.invalidOutput")
            }
        }
    }

    func testStoreRefreshesAndCompactPanelRenders() throws {
        let snapshot = DockerSnapshot(
            runningCount: 3, stoppedCount: 1, unhealthyCount: 0,
            cpuPercent: 4.2, memoryBytes: 512 * 1_048_576, observedAt: Date())
        let store = DockerStore(
            configuration: DockerConfiguration(),
            reader: FakeDockerReader(snapshot: snapshot))
        let loaded = expectation(description: "Docker loaded")
        var fulfilled = false
        let cancellable = store.$snapshot.sink {
            guard !fulfilled, $0 == snapshot else { return }
            fulfilled = true
            loaded.fulfill()
        }
        defer {
            store.stop()
            cancellable.cancel()
        }

        store.start()
        wait(for: [loaded], timeout: 2)

        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: DockerPanelView(store: store, theme: Theme.theme(id: ""))
                .frame(width: size.width, height: size.height))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
}
private struct FakeDockerReader: DockerReading {
    let snapshot: DockerSnapshot

    func read(now: Date, cancellation: Progress?) throws -> DockerSnapshot { snapshot }
}
