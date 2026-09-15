import Darwin
import SwiftTerm
import XCTest

@testable import DockDeck

final class BoundedProcessRunnerTests: XCTestCase {
    func testTerminalStopRemovesStubbornJobGroupsAndPreservesOtherProcesses() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["20"]
        try unrelated.run()
        defer { if unrelated.isRunning { unrelated.terminate() }; unrelated.waitUntilExit() }
        let probe = TerminalCleanupProbe()
        let process = LocalProcess(delegate: probe)
        process.startProcess(executable: "/bin/zsh", args: ["-f", "-m", "-c",
            #"trap '' TERM HUP; /bin/sh -c 'trap "" TERM HUP; printf "%s" $$ > "$1"; exec /bin/sleep 20' sh "$1" & wait"#,
            "zsh", marker.path])
        let pid = process.shellPid
        let session = try XCTUnwrap(TerminalShellSession(pid: pid))
        defer { session.stop { process.terminate() } }
        let readyDeadline = Date().addingTimeInterval(2)
        var childPID: Int32?
        while childPID == nil, Date() < readyDeadline {
            childPID = (try? String(contentsOf: marker, encoding: .utf8)).flatMap(Int32.init)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let child = try XCTUnwrap(childPID)
        XCTAssertEqual(getsid(child), pid)
        XCTAssertNotEqual(getpgid(child), getpgid(pid), "Exercise a separate job-control group")
        let started = Date()
        session.stop { process.terminate() }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.5)
        XCTAssertFalse(process.running)
        XCTAssertEqual(kill(pid, 0), -1)
        let reapingDeadline = Date().addingTimeInterval(1)
        while kill(child, 0) == 0, Date() < reapingDeadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertEqual(kill(child, 0), -1)
        XCTAssertTrue(unrelated.isRunning)
        session.stop { XCTFail("Already stopped shells must not receive another terminate") }
    }

    func testTerminalStopChecksPIDAfterSwiftTermReportsStopped() throws {
        let probe = TerminalCleanupProbe()
        let process = LocalProcess(delegate: probe)
        process.startProcess(executable: "/bin/sh", args: ["-c",
            "trap '' TERM HUP; printf READY; exec /bin/sleep 20"])
        let pid = process.shellPid
        let session = try XCTUnwrap(TerminalShellSession(pid: pid))
        defer { session.stop { process.terminate() } }
        let deadline = Date().addingTimeInterval(2)
        while !probe.ready, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(probe.ready)
        process.terminate()
        XCTAssertFalse(process.running, "SwiftTerm's stopped flag is not proof that the shell exited")
        XCTAssertEqual(kill(pid, 0), 0)
        session.stop {}
        XCTAssertEqual(kill(pid, 0), -1)
    }

    func testTerminalStopCleansJobsAfterShellAlreadyExited() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let probe = TerminalCleanupProbe()
        let process = LocalProcess(delegate: probe)
        process.startProcess(executable: "/bin/sh", args: ["-c",
            #"/bin/sh -c 'trap "" TERM HUP; printf "%s" $$ > "$1"; exec /bin/sleep 20' sh "$1" & while [ ! -s "$1" ]; do sleep 0.01; done; exit 0"#,
            "sh", marker.path])
        let session = try XCTUnwrap(TerminalShellSession(pid: process.shellPid))
        defer { session.stop { process.terminate() } }
        let deadline = Date().addingTimeInterval(2)
        while !probe.exited, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(probe.exited)
        let child = try XCTUnwrap(Int32(String(contentsOf: marker, encoding: .utf8)))
        XCTAssertEqual(kill(child, 0), 0)
        session.stop { XCTFail("An exited shell must not receive terminate") }
        let reapingDeadline = Date().addingTimeInterval(1)
        while kill(child, 0) == 0, Date() < reapingDeadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertEqual(kill(child, 0), -1)
    }

    func testTerminalSessionRejectsUnownedProcesses() {
        for pid: pid_t in [-1, 0, 1, getpid(), getppid()] {
            XCTAssertNil(TerminalShellSession(pid: pid))
        }
    }

    func testTimeoutCancellationAndShutdownRemoveStubbornDescendants() throws {
        for mode in ["timeout", "cancel", "shutdown"] {
            let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: marker) }
            let cancellation = Progress(totalUnitCount: 1)
            let lifetime = BoundedProcessLifetime()
            defer { cancellation.cancel(); lifetime.shutdown() }
            let finished = expectation(description: "Descendant cleaned up after \(mode)")
            DispatchQueue.global().async {
                do {
                    _ = try BoundedProcessRunner.run(
                        executableURL: URL(fileURLWithPath: "/bin/sh"),
                        arguments: ["-c", #"/bin/sh -c 'trap "" TERM; printf "%s" $$ > "$1"; exec /bin/sleep 20' sh "$1" & wait"#, "sh", marker.path],
                        timeout: mode == "timeout" ? 0.3 : 10, cancellation: cancellation, lifetime: lifetime)
                    XCTFail("Expected command cancellation or timeout")
                } catch {
                    XCTAssertEqual(error as? BoundedProcessError, mode == "timeout" ? .timedOut : .cancelled)
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
            defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
            if mode == "cancel" { cancellation.cancel() }
            if mode == "shutdown" { lifetime.shutdown() }
            wait(for: [finished], timeout: 4)
            XCTAssertEqual(kill(pid, 0), -1, "Surviving child after \(mode)")
            XCTAssertEqual(errno, ESRCH)
        }
    }

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

    func testAppShutdownWaitsForOwnedCommandsAndRejectsNewLaunches() throws {
        let lifetime = BoundedProcessLifetime()
        defer { lifetime.shutdown() }
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let finished = expectation(description: "Shutdown command finished")
        DispatchQueue.global().async {
            do {
                _ = try BoundedProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "trap '' TERM; printf '%s' $$ > \"$1\"; exec /bin/sleep 20", "sh", marker.path],
                    timeout: 10, lifetime: lifetime)
                XCTFail("Shutdown command returned success")
            } catch { XCTAssertEqual(error as? BoundedProcessError, .cancelled) }
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
        lifetime.shutdown()
        wait(for: [finished], timeout: 1)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 3)
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        XCTAssertThrowsError(try BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], lifetime: lifetime)) {
            XCTAssertEqual($0 as? BoundedProcessError, .cancelled)
        }
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

private final class TerminalCleanupProbe: LocalProcessDelegate {
    var ready = false
    var exited = false
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) { exited = true }
    func dataReceived(slice: ArraySlice<UInt8>) {
        ready = ready || String(decoding: slice, as: UTF8.self).contains("READY")
    }
    func getWindowSize() -> winsize {
        winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
    }
}
