import XCTest

@testable import DockDeck

final class ModuleRefreshTimerTests: XCTestCase {
    func testCadenceChangesPreserveElapsedTimeAndCancelReplacedTimer() throws {
        let anchor = Date().addingTimeInterval(-25)
        var timer = Timer.moduleRefreshTimer(interval: 60) {}
        timer.fireDate = anchor.addingTimeInterval(60)
        defer { timer.invalidate() }
        for interval: TimeInterval in [240, 60, 120, 480, 60, 240, 60] {
            let previous = timer
            timer = .moduleRefreshTimer(interval: interval, replacing: previous, preservingElapsed: true) {}
            XCTAssertFalse(previous.isValid)
            XCTAssertEqual(timer.fireDate.timeIntervalSince(anchor), interval, accuracy: 0.001)
        }
    }

    func testOverduePollFiresAfterReturningToForeground() {
        let fired = expectation(description: "Overdue foreground poll")
        let previous = Timer.moduleRefreshTimer(interval: 120) { XCTFail("Replaced timer fired") }
        previous.fireDate = Date().addingTimeInterval(30) // 90 seconds have elapsed.
        let timer = Timer.moduleRefreshTimer(interval: 60, replacing: previous, preservingElapsed: true) { fired.fulfill() }
        defer { timer.invalidate() }
        wait(for: [fired], timeout: 0.5)
    }

    func testStoppedTimerStartsWithANewInterval() {
        let previous = Timer.moduleRefreshTimer(interval: 60) {}
        previous.fireDate = Date().addingTimeInterval(-3_600)
        previous.invalidate()
        let timer = Timer.moduleRefreshTimer(interval: 120, replacing: previous, preservingElapsed: true) {}
        defer { timer.invalidate() }
        XCTAssertEqual(timer.fireDate.timeIntervalSinceNow, 120, accuracy: 0.1)
    }
}

extension XCTestCase {
    func assertCadenceKeepsPollingDeadline(
        _ runtime: any PanelModuleRuntime, interval: TimeInterval,
        backgroundMultiplier: Double, lowPowerMultiplier: Double = 2,
        deadline: () -> Date?, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let first = deadline() else { return XCTFail("Polling timer missing", file: file, line: line) }
        for _ in 0..<5 {
            for (activity, lowPower, multiplier): (ModuleRuntimeActivity, Bool, Double) in [
                (.background, false, backgroundMultiplier), (.visible, false, 1),
                (.background, true, backgroundMultiplier * lowPowerMultiplier),
                (.visible, true, lowPowerMultiplier), (.visible, false, 1),
            ] {
                runtime.setRuntimeActivity(activity, lowPowerMode: lowPower)
                guard let next = deadline() else { return XCTFail("Polling timer lost", file: file, line: line) }
                XCTAssertEqual(next.timeIntervalSince(first), interval * (multiplier - 1),
                    accuracy: 0.001, file: file, line: line)
            }
        }
    }
}
