import Foundation
import XCTest

@testable import DockDeck

final class UsageProviderTests: XCTestCase {
    func testSingleUsageWindowUsesSplitHeader() {
        XCTAssertEqual(UsageResetPlacement.forWindowCount(1), .splitHeader)
        XCTAssertEqual(UsageResetPlacement.forWindowCount(2), .below)
        XCTAssertEqual(UsageResetPlacement.forWindowCount(3), .below)
    }

    func testUsageProviderMarkAssetsMatchOfficialVariants() {
        XCTAssertEqual(
            UsageProviderMarkAsset.resourceName(for: .codex, dark: true),
            "OpenAI-Blossom-White")
        XCTAssertEqual(
            UsageProviderMarkAsset.resourceName(for: .codex, dark: false),
            "OpenAI-Blossom-Black")
        XCTAssertEqual(
            UsageProviderMarkAsset.resourceName(for: .claude, dark: true),
            "ClaudeIcon-Rounded")
        XCTAssertNotNil(UsageProviderMarkAsset.image(for: .codex, dark: true))
        XCTAssertNotNil(UsageProviderMarkAsset.image(for: .codex, dark: false))
        XCTAssertNotNil(UsageProviderMarkAsset.image(for: .claude, dark: true))
    }

    func testResetFormatterShowsLocalTimeAndDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 2, hour: 12))!
        let sameDay = calendar.date(bySettingHour: 18, minute: 5, second: 0, of: now)!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: sameDay)!

        XCTAssertEqual(
            UsageResetFormatter.compactString(for: sameDay, now: now, calendar: calendar),
            "18:05")
        XCTAssertEqual(
            UsageResetFormatter.compactString(for: nextDay, now: now, calendar: calendar),
            "9/3 18:05")
        XCTAssertEqual(
            UsageResetFormatter.compactString(for: nil, now: now, calendar: calendar),
            "--")
    }

    func testUsageStorePublishesOnlySelectedProvidersBeforeStarting() {
        let store = UsageStore()

        store.setEnabledProviders([.claude])

        XCTAssertEqual(store.providers.map(\.id), [.claude])
    }

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
        XCTAssertEqual(
            snapshot.windows.map(\.resetsAt),
            [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 3_000)])
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
        XCTAssertEqual(
            snapshot.windows.map(\.resetsAt),
            [
                Date(timeIntervalSince1970: 3_000), Date(timeIntervalSince1970: 4_000),
                Date(timeIntervalSince1970: 5_000),
            ])
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
