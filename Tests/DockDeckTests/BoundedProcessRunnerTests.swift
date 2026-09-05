import Darwin
import XCTest

@testable import DockDeck

final class BoundedProcessRunnerTests: XCTestCase {
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
