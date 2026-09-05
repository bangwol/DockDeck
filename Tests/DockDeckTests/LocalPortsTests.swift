import Darwin
import XCTest
@testable import DockDeck

final class LocalPortsTests: XCTestCase {
    func testPortConfigurationRejectsInvalidAndDuplicateInputs() {
        XCTAssertEqual(LocalPortsConfiguration.parse("3000, 5173 8080"), [3000, 5173, 8080])
        for text in ["", "0", "65536", "-1", "3,3", "localhost:3000", "1,2,3,4,5,6"] {
            XCTAssertNil(LocalPortsConfiguration.parse(text))
        }
        var configuration = LocalPortsConfiguration()
        configuration.ports = [0, 3000, 3000, 65536, 5173]
        configuration.refreshInterval = .infinity
        XCTAssertEqual(configuration.normalized().ports, [3000, 5173])
        XCTAssertEqual(configuration.normalized().refreshInterval, 30)
    }

    func testStoppingSkipsRemainingPortsAndLateResults() {
        let started = expectation(description: "Probe started")
        let reader = BlockingPortReader(started: started)
        let store = LocalPortsStore(reader: reader)
        store.start()
        wait(for: [started], timeout: 1)
        store.stop()
        reader.gate.signal()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testLoopbackProbeFindsListenerAndThenClosedPort() throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(listener, 0)
        guard listener >= 0 else { return }
        var closed = false
        defer { if !closed { close(listener) } }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(listener, 2), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        XCTAssertEqual(result, 0)
        let port = UInt16(bigEndian: address.sin_port)
        let reader = LocalPortReader()
        XCTAssertEqual(reader.state(port: port), .open)
        close(listener)
        closed = true
        XCTAssertEqual(reader.state(port: port), .closed)
    }
}

private final class BlockingPortReader: LocalPortReading {
    let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let started: XCTestExpectation
    private var count = 0
    var readCount: Int { lock.withLock { count } }
    init(started: XCTestExpectation) { self.started = started }
    func state(port: UInt16) -> LocalPortState {
        lock.withLock { count += 1 }
        started.fulfill()
        _ = gate.wait(timeout: .now() + 1)
        return .open
    }
}
