import Darwin
import XCTest
@testable import DockDeck

final class ModuleCancellationTests: XCTestCase {
    func testStoppingModulesCancelsReadersWithoutPublishingFailures() {
        for module in 0..<4 {
            let entered = expectation(description: "Reader entered")
            let finished = expectation(description: "Completion delivered")
            let reader = CancellationProbe(entered: entered)
            let queue = DispatchQueue(label: "DockDeck.CancellationTest")
            let tileStore = CustomTileStore(
                configuration: CustomTileConfiguration(executablePath: "/usr/bin/printf"), reader: reader, queue: queue)
            let dockerStore = DockerStore(reader: reader, queue: queue)
            let inboxStore = GitHubInboxStore(reader: reader, queue: queue)
            let projectStore = ProjectPulseStore(
                configuration: .init(source: .github, githubScope: .activity), reader: reader, queue: queue)
            let starts = [tileStore.start, dockerStore.start, inboxStore.start, projectStore.start]
            let stops = [tileStore.stop, dockerStore.stop, inboxStore.stop, projectStore.stop]
            starts[module]()
            wait(for: [entered], timeout: 2)
            stops[module]()
            queue.async { DispatchQueue.main.async { finished.fulfill() } }
            wait(for: [finished], timeout: 3)
            XCTAssertNil(tileStore.snapshot)
            XCTAssertNil(dockerStore.snapshot)
            XCTAssertNil(inboxStore.snapshot)
            XCTAssertNil(projectStore.snapshot)
            XCTAssertEqual(tileStore.status, .loading)
            XCTAssertEqual(dockerStore.status, .loading)
            XCTAssertEqual(inboxStore.status, .loading)
            XCTAssertEqual(projectStore.status, .loading)
        }
    }

    func testReleasedGitHubStoresCancelReaders() {
        for project in [false, true] {
            let entered = expectation(description: "Reader entered")
            let finished = expectation(description: "Reader released")
            let reader = CancellationProbe(entered: entered)
            let queue = DispatchQueue(label: "DockDeck.ReleaseTest")
            var inbox: GitHubInboxStore? = GitHubInboxStore(reader: reader, queue: queue)
            var pulse: ProjectPulseStore? = ProjectPulseStore(
                configuration: .init(source: .github, githubScope: .activity), reader: reader, queue: queue)
            weak var weakInbox = inbox
            weak var weakPulse = pulse
            if project { pulse?.start() } else { inbox?.start() }
            wait(for: [entered], timeout: 2)
            inbox = nil
            pulse = nil
            XCTAssertNil(weakInbox)
            XCTAssertNil(weakPulse)
            weakInbox = nil
            weakPulse = nil
            queue.async { DispatchQueue.main.async { finished.fulfill() } }
            wait(for: [finished], timeout: 3)
        }
    }

    func testBrokerCancelsQueuedWorkWithoutStoppingAnotherRequest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("pid")
        let unwanted = root.appendingPathComponent("must-not-run")
        let active = Progress(totalUnitCount: 1)
        defer { active.cancel() }
        let activeFinished = expectation(description: "Active command cancelled")
        DispatchQueue.global().async {
            do {
                _ = try GitHubCLIRequestBroker.shared.run(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "printf '%s' $$ > \"$1\"; exec /bin/sleep 10", "sh", marker.path],
                    currentDirectoryURL: root, environment: [:], cancellation: active)
                XCTFail("Expected active request cancellation")
            } catch { XCTAssertEqual(error as? BoundedProcessError, .cancelled) }
            activeFinished.fulfill()
        }
        let deadline = Date(timeIntervalSinceNow: 2)
        var observedPID: Int32?
        while observedPID == nil, Date() < deadline {
            observedPID = (try? String(contentsOf: marker, encoding: .utf8)).flatMap(Int32.init)
            if observedPID == nil { Thread.sleep(forTimeInterval: 0.01) }
        }
        let pid = try XCTUnwrap(observedPID)
        let queued = Progress(totalUnitCount: 1)
        let entered = expectation(description: "Queued request entered")
        let finished = expectation(description: "Queued request cancelled")
        DispatchQueue.global().async {
            entered.fulfill()
            do {
                _ = try GitHubCLIRequestBroker.shared.run(
                    executableURL: URL(fileURLWithPath: "/usr/bin/touch"), arguments: [unwanted.path],
                    currentDirectoryURL: root, environment: [:], cancellation: queued)
                XCTFail("Expected queued request cancellation")
            } catch { XCTAssertEqual(error as? BoundedProcessError, .cancelled) }
            finished.fulfill()
        }
        wait(for: [entered], timeout: 1)
        Thread.sleep(forTimeInterval: 0.1)
        queued.cancel()
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(kill(pid, 0), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unwanted.path))
        active.cancel()
        wait(for: [activeFinished], timeout: 2)
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testBrokerRejectsCancelledCacheHits() throws {
        let executable = URL(fileURLWithPath: "/usr/bin/printf")
        let directory = FileManager.default.temporaryDirectory
        let key = UUID().uuidString
        _ = try GitHubCLIRequestBroker.shared.run(executableURL: executable, arguments: ["cached"],
            currentDirectoryURL: directory, environment: [:], cacheKey: key, cacheDuration: 10)
        let cancellation = Progress(totalUnitCount: 1)
        cancellation.cancel()
        XCTAssertThrowsError(try GitHubCLIRequestBroker.shared.run(executableURL: executable,
            arguments: ["unexpected"], currentDirectoryURL: directory, environment: [:],
            cacheKey: key, cancellation: cancellation)) {
            XCTAssertEqual($0 as? BoundedProcessError, .cancelled)
        }
    }
}

private final class CancellationProbe: CustomTileReading, DockerReading, GitHubInboxReading, ProjectPulseReading {
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
    func read(configuration: GitHubInboxConfiguration, now: Date, cancellation: Progress?) throws -> GitHubInboxSnapshot {
        try waitForCancellation(cancellation)
        throw BoundedProcessError.cancelled
    }
    func read(configuration: ProjectPulseConfiguration, cancellation: Progress?) throws -> ProjectPulseSnapshot {
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
