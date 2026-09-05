import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class NetworkTests: XCTestCase {
    func testChangingInterfaceResetsBaselineAndHistory() {
        var bytes: UInt64 = 100
        let store = NetworkStore(interfaceName: "", counterReader: { name in
            defer { bytes += 100 }
            return NetworkCounters(interfaceName: name ?? "en0", receivedBytes: bytes, sentBytes: bytes)
        })
        store.refresh(now: Date(timeIntervalSince1970: 0))
        store.refresh(now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(store.snapshot?.downloadBytesPerSecond, 100)
        XCTAssertEqual(store.downloadHistory.samples.count, 1)
        store.setInterfaceName("utun0")
        XCTAssertTrue(store.downloadHistory.samples.isEmpty)
        store.refresh(now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(store.snapshot?.interfaceName, "utun0")
        XCTAssertNil(store.snapshot?.downloadBytesPerSecond)
        XCTAssertEqual(store.measurementStatus, "Measuring rate")
    }

    func testAutomaticRouteChangeAlsoClearsHistory() {
        var name = "en0"
        var bytes: UInt64 = 100
        let store = NetworkStore(interfaceName: "", counterReader: { _ in
            guard !name.isEmpty else { return nil }
            defer { bytes += 100 }
            return NetworkCounters(interfaceName: name, receivedBytes: bytes, sentBytes: bytes)
        })
        store.refresh(now: Date(timeIntervalSince1970: 0))
        store.refresh(now: Date(timeIntervalSince1970: 1))
        name = ""
        store.refresh(now: Date(timeIntervalSince1970: 1.5))
        name = "utun0"
        store.refresh(now: Date(timeIntervalSince1970: 2))
        XCTAssertTrue(store.downloadHistory.samples.isEmpty)
        XCTAssertNil(store.snapshot?.downloadBytesPerSecond)
    }

    func testUnavailableCountersAreDistinctFromOfflineRoute() {
        let store = NetworkStore(interfaceName: "en9", counterReader: { _ in nil })
        store.refresh()
        XCTAssertEqual(store.measurementStatus, "Counters unavailable")
        XCTAssertEqual(NetworkCounterReader.normalizedInterfaceName("en0\nignored"), "")
        XCTAssertEqual(NetworkCounterReader.normalizedInterfaceName(String(repeating: "x", count: 16)), "")
    }

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

    func testStoreTracksNativeConnectionMetadata() {
        let connection = NetworkConnectionSnapshot(
            status: .online, kind: .wifi, isExpensive: false, isConstrained: true)
        let observer = FakeNetworkPathObserver(snapshot: connection)
        let store = NetworkStore(refreshInterval: 2, pathObserver: observer)

        store.start()

        XCTAssertEqual(store.connection, connection)
        XCTAssertEqual(observer.startCount, 1)
        store.stop()
        XCTAssertEqual(observer.stopCount, 1)
    }

    func testPanelRendersAtCompactSize() throws {
        let store = NetworkStore(
            refreshInterval: 2,
            initialSnapshot: NetworkSnapshot(
                interfaceName: "en0",
                downloadBytesPerSecond: 1_572_864,
                uploadBytesPerSecond: 430_080),
            initialConnection: NetworkConnectionSnapshot(
                status: .online, kind: .wifi,
                isExpensive: false, isConstrained: false))
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

private final class FakeNetworkPathObserver: NetworkPathObserving {
    var onUpdate: ((NetworkConnectionSnapshot) -> Void)?
    private let snapshot: NetworkConnectionSnapshot
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(snapshot: NetworkConnectionSnapshot) { self.snapshot = snapshot }

    func start() {
        startCount += 1
        onUpdate?(snapshot)
    }

    func stop() { stopCount += 1 }
}
