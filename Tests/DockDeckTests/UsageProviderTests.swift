import Foundation
import XCTest

@testable import DockDeck

final class UsageProviderTests: XCTestCase {
    func testUsageWindowCalculatesRemainingPercentage() {
        XCTAssertEqual(
            UsageWindow(durationMinutes: 300, usedPercent: 22, resetsAt: nil).remainingPercent,
            78)
        XCTAssertEqual(
            UsageWindow(durationMinutes: 300, usedPercent: 120, resetsAt: nil).remainingPercent,
            0)
    }

    func testUsageDisplayModeChoosesRemainingOrUsedValue() {
        let window = UsageWindow(
            durationMinutes: 300, usedPercent: 22, resetsAt: nil)

        XCTAssertEqual(UsageDisplayMode.remaining.value(for: window), 78)
        XCTAssertEqual(UsageDisplayMode.used.value(for: window), 22)
    }

    func testCodexLaunchEnvironmentIncludesExecutableDirectory() {
        let executable = URL(fileURLWithPath: "/opt/codex/bin/codex")

        let environment = CodexBinaryLocator.launchEnvironment(
            for: executable,
            environment: ["PATH": "/usr/bin:/bin"])

        XCTAssertEqual(
            environment["PATH"],
            "/opt/codex/bin:/usr/bin:/bin")
    }

    func testCodexParserPrefersCodexBucketAndAllowsNullSecondary() throws {
        let data = Data(
            #"""
            {
              "id": 2,
              "result": {
                "rateLimits": {
                  "limitId": "legacy",
                  "primary": {
                    "usedPercent": 99,
                    "windowDurationMins": 300,
                    "resetsAt": 2000
                  },
                  "secondary": null
                },
                "rateLimitsByLimitId": {
                  "codex": {
                    "limitId": "codex",
                    "primary": {
                      "usedPercent": 18,
                      "windowDurationMins": 10080,
                      "resetsAt": 3000
                    },
                    "secondary": null,
                    "planType": "pro"
                  },
                  "codex_other": {
                    "limitId": "codex_other",
                    "primary": {
                      "usedPercent": 42,
                      "windowDurationMins": 300,
                      "resetsAt": 2500
                    }
                  }
                }
              }
            }
            """#.utf8)

        let envelope = try CodexRateLimitParser.decodeEnvelope(data)
        let result = try XCTUnwrap(envelope.result)
        let snapshot = try CodexRateLimitParser.snapshot(from: result)

        XCTAssertEqual(snapshot.freshness, .live)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].label, "7d")
        XCTAssertEqual(snapshot.windows[0].usedPercent, 18)
        XCTAssertEqual(snapshot.detail, "pro")
    }

    func testCodexParserBuildsDynamicWindowLabels() throws {
        let data = Data(
            #"""
            {
              "id": 2,
              "result": {
                "rateLimits": {
                  "limitId": "codex",
                  "primary": {
                    "usedPercent": 25,
                    "windowDurationMins": 300,
                    "resetsAt": 2000
                  },
                  "secondary": {
                    "usedPercent": 42,
                    "windowDurationMins": 10080,
                    "resetsAt": 3000
                  }
                }
              }
            }
            """#.utf8)

        let result = try XCTUnwrap(try CodexRateLimitParser.decodeEnvelope(data).result)
        let snapshot = try CodexRateLimitParser.snapshot(from: result)

        XCTAssertEqual(snapshot.windows.map(\.label), ["5h", "7d"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [25, 42])
    }

    func testClaudeParserReadsOnlyRateLimitsAndMarksFreshCacheLive() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let data = Data(
            #"""
            {
              "observed_at": 1900,
              "rate_limits": {
                "five_hour": {
                  "used_percentage": 35,
                  "resets_at": 3000
                },
                "seven_day": {
                  "used_percentage": 48,
                  "resets_at": 4000
                },
                "seven_day_fable": {
                  "used_percentage": 62,
                  "resets_at": 5000
                }
              }
            }
            """#.utf8)

        let snapshot = try ClaudeRateLimitParser.snapshot(
            from: data, modificationDate: nil, now: now)

        XCTAssertEqual(snapshot.freshness, .live)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5h", "7d", "FBL"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [35, 48, 62])
    }

    func testClaudeParserMarksExpiredWindowStale() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let data = Data(
            #"""
            {
              "observedAt": 1950,
              "rate_limits": {
                "five_hour": {
                  "used_percentage": 80,
                  "resets_at": 1999
                }
              }
            }
            """#.utf8)

        let snapshot = try ClaudeRateLimitParser.snapshot(
            from: data, modificationDate: nil, now: now)

        XCTAssertEqual(snapshot.freshness, .stale)
    }
}
