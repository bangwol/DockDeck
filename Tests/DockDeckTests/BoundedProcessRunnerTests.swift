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
