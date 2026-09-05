import XCTest
@testable import DockDeck

final class ModuleCancellationTests: XCTestCase {
    func testStoppingTilesAndDockerCancelsReadersWithoutPublishingFailures() {
        for tile in [true, false] {
            let entered = expectation(description: "Reader entered")
            let finished = expectation(description: "Completion delivered")
            let reader = CancellationProbe(entered: entered)
            let queue = DispatchQueue(label: "DockDeck.CancellationTest")
            let tileStore = CustomTileStore(
                configuration: CustomTileConfiguration(executablePath: "/usr/bin/printf"), reader: reader, queue: queue)
            let dockerStore = DockerStore(reader: reader, queue: queue)
            if tile { tileStore.start() } else { dockerStore.start() }
            wait(for: [entered], timeout: 2)
            if tile { tileStore.stop() } else { dockerStore.stop() }
            queue.async { DispatchQueue.main.async { finished.fulfill() } }
            wait(for: [finished], timeout: 3)
            XCTAssertNil(tileStore.snapshot)
            XCTAssertNil(dockerStore.snapshot)
            XCTAssertEqual(tileStore.status, .loading)
            XCTAssertEqual(dockerStore.status, .loading)
        }
    }
}

private final class CancellationProbe: CustomTileReading, DockerReading {
    let entered: XCTestExpectation
    init(entered: XCTestExpectation) { self.entered = entered }
    func read(configuration: CustomTileConfiguration, now: Date, cancellation: Progress?) throws -> CustomTileSnapshot {
        try waitForCancellation(cancellation)
        throw BoundedProcessError.cancelled
    }
    func read(now: Date, cancellation: Progress?) throws -> DockerSnapshot {
        try waitForCancellation(cancellation)
        throw BoundedProcessError.cancelled
    }
    private func waitForCancellation(_ cancellation: Progress?) throws {
        let signal = DispatchSemaphore(value: 0)
        cancellation?.cancellationHandler = { signal.signal() }
        defer { cancellation?.cancellationHandler = nil }
        entered.fulfill()
        if cancellation?.isCancelled != true { _ = signal.wait(timeout: .now() + 2) }
        XCTAssertEqual(cancellation?.isCancelled, true)
    }
}
