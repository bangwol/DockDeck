import Darwin
import XCTest

@testable import DockDeck

final class BoundedProcessRunnerTests: XCTestCase {
    func testCancelledRequestNeverLaunches() {
        let cancellation = Progress(totalUnitCount: 1)
        cancellation.cancel()
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/touch"), arguments: [marker.path], cancellation: cancellation)) {
            XCTAssertEqual($0 as? BoundedProcessError, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCancellationStopsTheOwnedProcessPromptly() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let cancellation = Progress(totalUnitCount: 1)
        let finished = expectation(description: "Cancelled process finished")
        defer { cancellation.cancel() }
        DispatchQueue.global().async {
            do {
                _ = try BoundedProcessRunner.run(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "printf '%s' $$ > \"$1\"; exec /bin/sleep 20", "sh", marker.path],
                    timeout: 10, cancellation: cancellation)
                XCTFail("Cancelled process returned success")
            } catch {
                XCTAssertEqual(error as? BoundedProcessError, .cancelled)
            }
            finished.fulfill()
        }
        let deadline = Date(timeIntervalSinceNow: 2)
        var observedPID: Int32?
        while observedPID == nil, Date() < deadline {
            observedPID = (try? String(contentsOf: marker, encoding: .utf8)).flatMap(Int32.init)
            if observedPID == nil { Thread.sleep(forTimeInterval: 0.01) }
        }
        let pid = try XCTUnwrap(observedPID)
        let started = ProcessInfo.processInfo.systemUptime
        cancellation.cancel()
        wait(for: [finished], timeout: 3)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2)
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testContinuousWriterCannotBlockOutputLimitCleanup() {
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; while :; do printf 'continuous output'; done"],
            timeout: 10, maximumOutputBytes: 16_384)) {
            XCTAssertEqual($0 as? BoundedProcessError, .outputTooLarge)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 3)
    }

    func testDiagnosticsKeepFailureCategoriesAndLastSuccess() {
        XCTAssertEqual(DiagnosticCommandRunner.run(URL(fileURLWithPath: "/no-such-dockdeck-command"), arguments: []), .failed)
        XCTAssertEqual(DiagnosticCommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"], timeout: 0.1), .timedOut)
        let metrics = ProcessDiagnostics()
        let success = Date(timeIntervalSince1970: 100)
        metrics.record(source: .customTile, duration: 0.1, failure: nil, now: success)
        metrics.record(source: .customTile, duration: 2, failure: .timedOut)
        metrics.record(source: .customTile, duration: 0.2, failure: .cancelled)
        let item = metrics.snapshot().first
        XCTAssertEqual(item?.lastSuccessfulAt, success)
        XCTAssertEqual(item?.lastDuration, 0.2)
        XCTAssertEqual(item?.timeouts, 1)
        XCTAssertEqual(item?.cancellations, 1)
        let report = DiagnosticsReportBuilder.build(items: [], runtime: .empty,
            appVersion: "test", operatingSystem: "test", architecture: "test", processes: metrics.snapshot())
        XCTAssertTrue(report.contains("Custom Tiles: 0.200s; timeouts 1; cancellations 1"))
    }

    func testRunnerCanReturnAllowedNonzeroExitOutput() throws {
        let output = try BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf accepted; exit 7"],
            allowedExitStatuses: [0, 7])

        XCTAssertEqual(String(data: output, encoding: .utf8), "accepted")
    }

    func testReturnsBoundedStandardOutput() throws {
        let output = try BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["ready"],
            timeout: 1,
            maximumOutputBytes: 16)

        XCTAssertEqual(String(data: output, encoding: .utf8), "ready")
    }

    func testReportsNonZeroExitWithoutReturningStderr() {
        XCTAssertThrowsError(
            try BoundedProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf private-error >&2; exit 7"],
                timeout: 1,
                maximumOutputBytes: 64)
        ) { error in
            XCTAssertEqual(error as? BoundedProcessError, .nonZeroExit(7))
        }
    }

    func testClosedOutputDoesNotSpinWhileProcessIsRunning() throws {
        func cpuTime() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let started = cpuTime()
        let output = try BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf ready; exec 1>&- 2>&-; /bin/sleep 0.5"],
            timeout: 2)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "ready")
        XCTAssertLessThan(cpuTime() - started, 0.35)
    }

    func testClosingStderrKeepsReadingStdout() throws {
        let output = try BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exec 2>&-; /bin/sleep 0.1; printf late"],
            timeout: 2)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "late")
    }

    func testStopsCommandsAtTimeout() {
        XCTAssertThrowsError(
            try BoundedProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                timeout: 0.05,
                maximumOutputBytes: 16)
        ) { error in
            XCTAssertEqual(error as? BoundedProcessError, .timedOut)
        }
    }
}
