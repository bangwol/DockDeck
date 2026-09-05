import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class UsageProviderTests: XCTestCase {
    func testQuotaWarningColorsUseRemainingCapacityBoundaries() {
        for (remaining, expected) in [(0.0, Color.red), (19.99, .red), (20, .orange),
                                      (30, .orange), (50, .orange), (50.01, .purple)] {
            let window = UsageWindow(durationMinutes: 300, usedPercent: 100 - remaining,
                                     resetsAt: nil)
            XCTAssertEqual(usageMeterColor(for: window, normal: .purple), expected)
        }
        XCTAssertEqual(UsageStore().refreshPlan(for: .codex), "Automatic updates paused")
    }

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

    func testUsageProviderMarkStateSeparatesStaleAndDisconnected() {
        XCTAssertEqual(UsageProviderMarkState.resolved(from: .live), .normal)
        XCTAssertEqual(UsageProviderMarkState.resolved(from: .loading), .muted)
        XCTAssertEqual(UsageProviderMarkState.resolved(from: .stale), .muted)
        XCTAssertEqual(UsageProviderMarkState.resolved(from: .signIn), .disconnected)
        XCTAssertEqual(UsageProviderMarkState.resolved(from: .unavailable), .disconnected)
        XCTAssertEqual(UsageProviderMarkState.resolved(from: .setupRequired), .disconnected)
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

    func testUsagePaceComparesUsageWithElapsedWindowTime() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = UsageWindow(
            durationMinutes: 100,
            usedPercent: 40,
            resetsAt: now.addingTimeInterval(75 * 60))

        let pace = try XCTUnwrap(UsagePace.calculate(for: window, now: now))

        XCTAssertEqual(pace.expectedUsedPercent, 25, accuracy: 0.001)
        XCTAssertEqual(pace.differenceFromEvenPace, 15, accuracy: 0.001)
        XCTAssertEqual(pace.markerValue(for: .used), 25, accuracy: 0.001)
        XCTAssertEqual(pace.markerValue(for: .remaining), 75, accuracy: 0.001)
        XCTAssertTrue(pace.helpText.contains("15 points above pace"))
    }

    func testUsagePaceRequiresAnActiveKnownDurationWindow() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertNil(
            UsagePace.calculate(
                for: UsageWindow(
                    durationMinutes: 300, usedPercent: 10, resetsAt: nil),
                now: now))
        XCTAssertNil(
            UsagePace.calculate(
                for: UsageWindow(
                    durationMinutes: 0, usedPercent: 10,
                    resetsAt: now.addingTimeInterval(60), customLabel: "FBL"),
                now: now))
        XCTAssertNil(
            UsagePace.calculate(
                for: UsageWindow(
                    durationMinutes: 300, usedPercent: 10,
                    resetsAt: now.addingTimeInterval(-1)),
                now: now))
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

    func testCodexProviderHandlesNotificationsBeforeAndAfterResponse() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDeckCodexNotifications-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        try Data(
            #"""
            #!/bin/sh
            IFS= read -r initialize
            IFS= read -r initialized
            IFS= read -r request
            printf '%s\n' \
              '{"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300}}}}' \
              '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":18,"windowDurationMins":300}}}}' \
              '{"method":"unrelated/updated","params":{}}' \
              '{"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"usedPercent":42,"windowDurationMins":300}}}}'
            while IFS= read -r request; do :; done
            """#.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let provider = CodexAppServerProvider(executableURL: executable)
        defer { provider.stop() }
        let received = expectation(description: "Response and notifications received")
        received.expectedFulfillmentCount = 3
        var percentages: [Double] = []
        provider.start { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let snapshot):
                    percentages.append(contentsOf: snapshot.windows.map(\.usedPercent))
                    received.fulfill()
                case .failure(let error):
                    XCTFail("Unexpected provider failure: \(error)")
                }
            }
        }

        wait(for: [received], timeout: 3)
        XCTAssertEqual(percentages, [10, 18, 42])
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

    func testClaudeUsageCommandParserReadsSessionWeekAndFable() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let capturedAt = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 2, hour: 20)))
        let output = """
            You are currently using your subscription to power your Claude Code usage

            Current session: 0% used · resets Sep 2 at 11:19pm (Asia/Seoul)
            Current week (all models): 19% used · resets Sep 4 at 4:59am (Asia/Seoul)
            Current week (Fable): 31% used · resets Sep 4 at 4:59am (Asia/Seoul)
            """

        let snapshot = try ClaudeUsageCommandParser.parse(output, capturedAt: capturedAt)

        XCTAssertEqual(snapshot.windows.map(\.label), ["5h", "7d", "FBL"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [0, 19, 31])
        XCTAssertEqual(
            snapshot.windows[0].resetsAt,
            calendar.date(from: DateComponents(
                year: 2026, month: 9, day: 2, hour: 23, minute: 19)))
        XCTAssertEqual(
            snapshot.windows[1].resetsAt,
            calendar.date(from: DateComponents(
                year: 2026, month: 9, day: 4, hour: 4, minute: 59)))
        XCTAssertEqual(snapshot.freshness, .live)
        XCTAssertEqual(snapshot.observedAt, capturedAt)
    }

    func testClaudeUsageCommandParserReadsRenderedMultilineScreen() throws {
        let capturedAt = Date(timeIntervalSince1970: 2_000)
        let output = """
            Current session
            █████                                      12% used
            Resets in 2h 30m

            Current week (all models)
            ███████████                                22% used
            Resets in 3 days

            Current week (Fable)
            ███████████████                            30% used
            Resets in 3 days
            """

        let snapshot = try ClaudeUsageCommandParser.parse(output, capturedAt: capturedAt)

        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [12, 22, 30])
        XCTAssertEqual(
            snapshot.windows[0].resetsAt,
            capturedAt.addingTimeInterval((2 * 60 + 30) * 60))
        XCTAssertEqual(
            snapshot.windows[2].resetsAt,
            capturedAt.addingTimeInterval(3 * 24 * 60 * 60))
    }

    func testClaudeUsageCommandParserRejectsAuthenticationScreen() {
        XCTAssertThrowsError(
            try ClaudeUsageCommandParser.parse("Not logged in. Please log in to continue.")) {
                guard case UsageProviderError.authenticationRequired = $0 else {
                    return XCTFail("Expected authenticationRequired, got \($0)")
                }
            }
        XCTAssertThrowsError(
            try ClaudeUsageCommandParser.parse(
                "OAuth unavailable: Claude OAuth authorization expired; sign in again.")) {
                guard case UsageProviderError.authenticationRequired = $0 else {
                    return XCTFail("Expected authenticationRequired, got \($0)")
                }
            }
    }

    func testClaudeProviderFallsBackToHiddenPTY() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDeckClaudePTY-\(UUID().uuidString)", isDirectory: true)
        let executable = root.appendingPathComponent("claude")
        let probeDirectory = root.appendingPathComponent("probe", isDirectory: true)
        let homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: homeDirectory, withIntermediateDirectories: true)
        try Data(
            """
            #!/bin/sh
            case " $* " in
              *" /usage "*) echo "direct mode unavailable"; exit 0 ;;
            esac
            printf '❯ '
            while IFS= read -r line; do
              case "$line" in
                *"/usage"*)
                  printf '\nCurrent session\n10%% used\nResets in 2h\n'
                  printf '\nCurrent week (all models)\n20%% used\nResets in 3 days\n'
                  printf '\nCurrent week (Fable)\n30%% used\nResets in 3 days\n'
                  ;;
              esac
            done
            """.utf8
        ).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let provider = ClaudeUsageCommandProvider(
            environment: [
                "DOCKDECK_CLAUDE_PATH": executable.path,
                "PATH": "/usr/bin:/bin",
            ],
            homeDirectory: homeDirectory,
            probeDirectory: probeDirectory)

        let result = provider.read(now: Date(timeIntervalSince1970: 2_000))

        guard case .success(let snapshot) = result else {
            return XCTFail("Expected the hidden PTY fallback to return usage")
        }
        XCTAssertEqual(snapshot.windows.map(\.label), ["5h", "7d", "FBL"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [10, 20, 30])
    }

    func testClaudeProviderReturnsWithoutWaitingForInheritedPipeWriters() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("DockDeckClaudePipe-\(UUID().uuidString)")
        let executable = root.appendingPathComponent("claude")
        let homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try Data(
            """
            #!/bin/sh
            (sleep 4) &
            printf 'Current session\n10%% used\nResets in 2h\n'
            printf 'Current week (all models)\n20%% used\nResets in 3 days\n'
            """.utf8
        ).write(to: executable)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let provider = ClaudeUsageCommandProvider(
            environment: [
                "DOCKDECK_CLAUDE_PATH": executable.path,
                "PATH": "/usr/bin:/bin",
            ],
            homeDirectory: homeDirectory,
            probeDirectory: root.appendingPathComponent("probe", isDirectory: true))

        for _ in 0..<3 {
            let startedAt = Date()
            guard case .success = provider.read(now: Date(timeIntervalSince1970: 2_000)) else {
                return XCTFail("Expected direct Claude usage output to parse repeatedly")
            }
            // Each inherited writer remains open for four seconds. Check each read
            // independently so unrelated process-launch overhead does not accumulate.
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
        }
    }

    func testClaudeProviderCancellationReturnsPromptly() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("DockDeckClaudeCancel-\(UUID().uuidString)")
        let executable = root.appendingPathComponent("claude")
        let homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nsleep 5\n".utf8).write(to: executable)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let provider = ClaudeUsageCommandProvider(
            environment: [
                "DOCKDECK_CLAUDE_PATH": executable.path,
                "PATH": "/usr/bin:/bin",
            ],
            homeDirectory: homeDirectory,
            probeDirectory: root.appendingPathComponent("probe", isDirectory: true))
        let finished = expectation(description: "Cancelled Claude probe returns")
        let startedAt = Date()

        DispatchQueue.global(qos: .utility).async {
            _ = provider.read(now: Date(timeIntervalSince1970: 2_000))
            finished.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.1)
        provider.cancel()
        wait(for: [finished], timeout: 2)

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    func testClaudeProviderRemovesLateSessionArtifact() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("DockDeckClaudeCleanup-\(UUID().uuidString)", isDirectory: true)
        let executable = root.appendingPathComponent("claude")
        let probeDirectory = root.appendingPathComponent("probe", isDirectory: true)
        let homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        let encodedProbe = String(probeDirectory.path.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 48...57, 65...90, 97...122: Character(scalar)
            default: "-"
            }
        })
        let projectDirectory = homeDirectory
            .appendingPathComponent(".claude/projects", isDirectory: true)
            .appendingPathComponent(encodedProbe, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try Data(
            """
            #!/bin/sh
            session_id=''
            while [ "$#" -gt 0 ]; do
              if [ "$1" = '--session-id' ]; then shift; session_id="$1"; fi
              shift
            done
            (
              sleep 0.15
              mkdir -p "$TEST_PROJECT_DIR"
              printf '{}\n' > "$TEST_PROJECT_DIR/$session_id.jsonl"
            ) >/dev/null 2>&1 &
            printf 'Current session\n10%% used\nResets in 2h\n'
            """.utf8
        ).write(to: executable)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let provider = ClaudeUsageCommandProvider(
            environment: [
                "DOCKDECK_CLAUDE_PATH": executable.path,
                "PATH": "/usr/bin:/bin",
                "TEST_PROJECT_DIR": projectDirectory.path,
            ],
            homeDirectory: homeDirectory,
            probeDirectory: probeDirectory)

        guard case .success = provider.read(now: Date(timeIntervalSince1970: 2_000)) else {
            return XCTFail("Expected direct Claude usage output to parse")
        }
        XCTAssertFalse(fileManager.fileExists(atPath: projectDirectory.path))
    }

    func testClaudeProviderStripsCredentialOverrides() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("DockDeckClaudeEnvironment-\(UUID().uuidString)")
        let executable = root.appendingPathComponent("claude")
        let homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try Data(
            """
            #!/bin/sh
            if [ -n "${ANTHROPIC_API_KEY:-}" ] \
              || [ -n "${CLAUDE_CODE_OAUTH_TOKEN_FUTURE:-}" ]; then
              printf 'credential override leaked\n'
              exit 1
            fi
            printf 'Current session\n10%% used\nResets in 2h\n'
            """.utf8
        ).write(to: executable)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let provider = ClaudeUsageCommandProvider(
            environment: [
                "ANTHROPIC_API_KEY": "sentinel",
                "CLAUDE_CODE_OAUTH_TOKEN_FUTURE": "sentinel",
                "DOCKDECK_CLAUDE_PATH": executable.path,
                "PATH": "/usr/bin:/bin",
            ],
            homeDirectory: homeDirectory,
            probeDirectory: root.appendingPathComponent("probe", isDirectory: true))

        guard case .success = provider.read(now: Date(timeIntervalSince1970: 2_000)) else {
            return XCTFail("Expected credential overrides to be stripped")
        }
    }

    func testClaudeUsageSnapshotMergerKeepsProbeOnlyFableWindow() throws {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let command = UsageProviderSnapshot(
            windows: [
                UsageWindow(durationMinutes: 300, usedPercent: 10, resetsAt: nil),
                UsageWindow(
                    durationMinutes: 0, usedPercent: 30, resetsAt: nil,
                    customLabel: "FBL"),
            ],
            freshness: .live,
            detail: "command",
            observedAt: older)
        let bridge = UsageProviderSnapshot(
            windows: [
                UsageWindow(durationMinutes: 300, usedPercent: 12, resetsAt: nil),
                UsageWindow(durationMinutes: 10_080, usedPercent: 20, resetsAt: nil),
            ],
            freshness: .live,
            detail: "bridge",
            observedAt: newer)

        let merged = try XCTUnwrap(ClaudeUsageSnapshotMerger.merge([bridge, command]))

        XCTAssertEqual(merged.windows.map(\.label), ["5h", "7d", "FBL"])
        XCTAssertEqual(merged.windows.map(\.usedPercent), [12, 20, 30])
        XCTAssertEqual(merged.detail, "bridge")
        XCTAssertEqual(merged.observedAt, newer)
    }

    func testClaudeProbeScheduleStaysWithinTenToTwentyMinutes() {
        XCTAssertEqual(ClaudeUsageProbeSchedule.delay(unitValue: -1), 600)
        XCTAssertEqual(ClaudeUsageProbeSchedule.delay(unitValue: 0.5), 900)
        XCTAssertEqual(ClaudeUsageProbeSchedule.delay(unitValue: 2), 1_200)
    }

    func testClaudeProbeScheduleWaitsForLatestBlockingReset() {
        let now = Date(timeIntervalSince1970: 1_000)
        let windows = [
            UsageWindow(
                durationMinutes: 300, usedPercent: 100,
                resetsAt: now.addingTimeInterval(1_800)),
            UsageWindow(
                durationMinutes: 10_080, usedPercent: 100,
                resetsAt: now.addingTimeInterval(7_200)),
            UsageWindow(
                durationMinutes: 0, usedPercent: 100,
                resetsAt: now.addingTimeInterval(20_000), customLabel: "FBL"),
        ]

        XCTAssertEqual(
            ClaudeUsageProbeSchedule.nextDelay(proposed: 900, windows: windows, now: now),
            7_200 + ClaudeUsageProbeSchedule.resetGraceDelay)
    }

    func testClaudeProbeScheduleUsesHourlyFallbackWithoutReset() {
        let now = Date(timeIntervalSince1970: 1_000)
        let windows = [
            UsageWindow(durationMinutes: 300, usedPercent: 100, resetsAt: nil)
        ]

        XCTAssertEqual(
            ClaudeUsageProbeSchedule.nextDelay(proposed: 900, windows: windows, now: now),
            ClaudeUsageProbeSchedule.exhaustedFallbackDelay)
    }

    func testClaudeProbeScheduleIgnoresFableAndExpiredResets() {
        let now = Date(timeIntervalSince1970: 1_000)
        let windows = [
            UsageWindow(
                durationMinutes: 300, usedPercent: 100,
                resetsAt: now.addingTimeInterval(-1)),
            UsageWindow(
                durationMinutes: 0, usedPercent: 100,
                resetsAt: now.addingTimeInterval(20_000), customLabel: "FBL"),
        ]

        XCTAssertEqual(
            ClaudeUsageProbeSchedule.nextDelay(proposed: 900, windows: windows, now: now),
            900)
    }

    func testUsageStorePausesProbeUntilSystemBecomesActive() {
        let snapshot = UsageProviderSnapshot(
            windows: [UsageWindow(durationMinutes: 300, usedPercent: 15, resetsAt: nil)],
            freshness: .live,
            detail: "command",
            observedAt: Date())
        let command = FakeClaudeUsageCommandProvider(result: .success(snapshot))
        let cache = ClaudeStatuslineCacheProvider(cacheURL: missingCacheURL())
        let queue = DispatchQueue(label: "DockDeckTests.ClaudeProbe")
        let store = UsageStore(
            claudeProvider: cache,
            claudeCommandProvider: command,
            nextClaudeProbeDelay: { 1_200 },
            claudeProbeQueue: queue)
        store.setEnabledProviders([.claude])
        store.setSystemRefreshActive(false)
        store.start()
        queue.sync {}
        XCTAssertEqual(command.readCount, 0)

        let loaded = expectation(description: "Claude probe loaded")
        var fulfilled = false
        let cancellable = store.$providers.sink { providers in
            guard !fulfilled, providers.first?.windows.first?.usedPercent == 15 else { return }
            fulfilled = true
            loaded.fulfill()
        }
        store.setSystemRefreshActive(true)
        wait(for: [loaded], timeout: 2)

        XCTAssertEqual(command.readCount, 1)
        store.stop()
        cancellable.cancel()
    }

    func testExhaustedClaudeProbeWaitsAfterWakeButPanelRefreshOverrides() {
        let snapshot = UsageProviderSnapshot(
            windows: [
                UsageWindow(
                    durationMinutes: 300, usedPercent: 100,
                    resetsAt: Date().addingTimeInterval(3_600))
            ],
            freshness: .live,
            detail: "command",
            observedAt: Date())
        let command = FakeClaudeUsageCommandProvider(result: .success(snapshot))
        let cache = ClaudeStatuslineCacheProvider(cacheURL: missingCacheURL())
        let queue = DispatchQueue(label: "DockDeckTests.ExhaustedClaudeProbe")
        var uptime: TimeInterval = 100
        let store = UsageStore(
            claudeProvider: cache,
            claudeCommandProvider: command,
            nextClaudeProbeDelay: { 600 },
            claudeProbeQueue: queue,
            uptime: { uptime })
        store.setEnabledProviders([.claude])
        let loaded = expectation(description: "Exhausted Claude usage loaded")
        var fulfilled = false
        let cancellable = store.$providers.sink { providers in
            guard !fulfilled, providers.first?.windows.first?.remainingPercent == 0 else {
                return
            }
            fulfilled = true
            loaded.fulfill()
        }
        let previousConfiguration = PanelSettings.deckConfiguration
        let previousRight = PanelSettings.activeModule(on: .right)
        defer {
            store.stop()
            cancellable.cancel()
            PanelSettings.deckConfiguration = previousConfiguration
            PanelSettings.setActiveModule(previousRight, on: .right)
        }

        store.start()
        wait(for: [loaded], timeout: 2)
        XCTAssertEqual(command.readCount, 1)

        store.setSystemRefreshActive(false)
        store.setSystemRefreshActive(true)
        queue.sync {}
        XCTAssertEqual(command.readCount, 1)

        store.refresh()
        store.refresh()
        queue.sync {}
        XCTAssertEqual(command.readCount, 1)

        PanelSettings.deckConfiguration = PanelDeckConfiguration(
            left: [.terminal], right: [.usage], enabled: [.terminal, .usage])
        PanelSettings.setActiveModule(.usage, on: .right)
        let controller = ReadOnlyDeckPanelController(
            initialFrame: NSRect(x: 0, y: 0, width: 214, height: 59),
            theme: Theme.theme(id: ""),
            services: PanelModuleServices(usage: store),
            menuTarget: NSObject(),
            side: .right)

        uptime += 61
        XCTAssertTrue(controller.refreshUsageIfActive(at: 100))
        queue.sync {}
        XCTAssertEqual(command.readCount, 2)

        XCTAssertFalse(controller.refreshUsageIfActive(at: 100.5))
        XCTAssertTrue(controller.refreshUsageIfActive(at: 100.75))
        queue.sync {}
        XCTAssertEqual(command.readCount, 2)
    }

    func testUsageStoreStatusLineModeDoesNotLaunchClaude() {
        let command = FakeClaudeUsageCommandProvider(
            result: .failure(.transport("Should not run")))
        let queue = DispatchQueue(label: "DockDeckTests.ClaudeStatusLineOnly")
        let store = UsageStore(
            claudeProvider: ClaudeStatuslineCacheProvider(cacheURL: missingCacheURL()),
            claudeCommandProvider: command,
            nextClaudeProbeDelay: { 600 },
            claudeProbeQueue: queue)
        store.setEnabledProviders([.claude])
        store.setClaudeRefreshMode(.statusLineOnly)
        XCTAssertEqual(command.cancelCount, 1)
        store.start()
        store.refresh()
        store.refreshClaudeUsageIfDue()
        store.setSystemRefreshActive(false)
        store.setSystemRefreshActive(true)
        queue.sync {}

        XCTAssertEqual(command.readCount, 0)
        store.stop()
    }

    func testUsageStoreWatchdogCancelsStuckClaudeProbe() {
        let command = BlockingClaudeUsageCommandProvider()
        let store = UsageStore(
            claudeProvider: ClaudeStatuslineCacheProvider(cacheURL: missingCacheURL()),
            claudeCommandProvider: command,
            nextClaudeProbeDelay: { 1_200 },
            claudeProbeTimeout: 0.05,
            claudeProbeQueue: DispatchQueue(label: "DockDeckTests.ClaudeWatchdog"))
        store.setEnabledProviders([.claude])
        let timedOut = expectation(description: "Claude watchdog publishes timeout")
        var fulfilled = false
        let cancellable = store.$providers.sink { providers in
            guard !fulfilled, providers.first?.detail?.contains("refresh timed out") == true else {
                return
            }
            fulfilled = true
            timedOut.fulfill()
        }
        defer {
            store.stop()
            cancellable.cancel()
        }

        store.start()
        store.refresh()
        store.refresh()
        store.refresh()
        wait(for: [timedOut], timeout: 2)

        XCTAssertEqual(command.readCount, 1)
        XCTAssertGreaterThanOrEqual(command.cancelCount, 1)
    }

    func testUsageStoreShowsProbeFailureAlongsideCachedClaudeUsage() throws {
        let cacheURL = missingCacheURL()
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let now = Date().timeIntervalSince1970
        try Data(
            """
            {
              "observedAt": \(now),
              "rate_limits": {
                "five_hour": {"used_percentage": 20, "resets_at": \(now + 3600)}
              }
            }
            """.utf8
        ).write(to: cacheURL)
        let command = FakeClaudeUsageCommandProvider(
            result: .failure(.transport("Automatic probe failed")))
        let store = UsageStore(
            claudeProvider: ClaudeStatuslineCacheProvider(cacheURL: cacheURL),
            claudeCommandProvider: command,
            nextClaudeProbeDelay: { 1_200 },
            claudeProbeQueue: DispatchQueue(label: "DockDeckTests.ClaudeCachedError"))
        store.setEnabledProviders([.claude])
        let published = expectation(description: "Cached usage includes automatic probe error")
        var fulfilled = false
        let cancellable = store.$providers.sink { providers in
            guard !fulfilled, let provider = providers.first,
                provider.windows.first?.usedPercent == 20,
                provider.detail?.contains("Automatic probe failed") == true
            else { return }
            fulfilled = true
            XCTAssertEqual(provider.freshness, .stale)
            published.fulfill()
        }
        defer {
            store.stop()
            cancellable.cancel()
        }

        store.start()
        wait(for: [published], timeout: 2)
    }

    func testUsagePanelRendersThreeClaudeWindowsAtCompactSize() throws {
        let snapshot = UsageProviderSnapshot(
            windows: [
                UsageWindow(durationMinutes: 300, usedPercent: 12, resetsAt: Date() + 7_200),
                UsageWindow(
                    durationMinutes: 10_080, usedPercent: 24, resetsAt: Date() + 259_200),
                UsageWindow(
                    durationMinutes: 0, usedPercent: 36, resetsAt: Date() + 259_200,
                    customLabel: "FBL"),
            ],
            freshness: .live,
            detail: "Claude /usage",
            observedAt: Date())
        let command = FakeClaudeUsageCommandProvider(result: .success(snapshot))
        let queue = DispatchQueue(label: "DockDeckTests.ClaudeThreeWindowPanel")
        let store = UsageStore(
            claudeProvider: ClaudeStatuslineCacheProvider(cacheURL: missingCacheURL()),
            claudeCommandProvider: command,
            nextClaudeProbeDelay: { 1_200 },
            claudeProbeQueue: queue)
        store.setEnabledProviders([.claude])
        let loaded = expectation(description: "Three Claude usage windows loaded")
        var fulfilled = false
        let cancellable = store.$providers.sink { providers in
            guard !fulfilled, providers.first?.windows.count == 3 else { return }
            fulfilled = true
            loaded.fulfill()
        }
        defer {
            store.stop()
            cancellable.cancel()
        }
        store.start()
        wait(for: [loaded], timeout: 2)
        XCTAssertEqual(store.providers.first?.windows.map(\.label), ["5h", "7d", "FBL"])

        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(rootView:
            QuotaPanelView(
                store: store,
                theme: Theme.theme(id: ""),
                configuration: UsagePanelConfiguration(
                    displayMode: .remaining, fontName: "Menlo", fontSize: 10,
                    textColor: .theme, showsPace: true))
                .frame(width: size.width, height: size.height))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    private func missingCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDeckTests-\(UUID().uuidString)")
            .appendingPathComponent("claude-rate-limits.json")
    }
}

private final class FakeClaudeUsageCommandProvider: ClaudeUsageCommandReading {
    private let lock = NSLock()
    private let result: Result<UsageProviderSnapshot, UsageProviderError>
    private var storedReadCount = 0
    private var storedCancelCount = 0

    init(result: Result<UsageProviderSnapshot, UsageProviderError>) {
        self.result = result
    }

    var readCount: Int { lock.withLock { storedReadCount } }
    var cancelCount: Int { lock.withLock { storedCancelCount } }

    func read(now: Date) -> Result<UsageProviderSnapshot, UsageProviderError> {
        lock.withLock { storedReadCount += 1 }
        return result
    }

    func cancel() { lock.withLock { storedCancelCount += 1 } }
}

private final class BlockingClaudeUsageCommandProvider: ClaudeUsageCommandReading {
    private let lock = NSLock()
    private let cancelled = DispatchSemaphore(value: 0)
    private var storedReadCount = 0
    private var storedCancelCount = 0

    var readCount: Int { lock.withLock { storedReadCount } }
    var cancelCount: Int { lock.withLock { storedCancelCount } }

    func read(now: Date) -> Result<UsageProviderSnapshot, UsageProviderError> {
        lock.withLock { storedReadCount += 1 }
        _ = cancelled.wait(timeout: .now() + 5)
        return .failure(.transport("Cancelled by watchdog"))
    }

    func cancel() {
        lock.withLock { storedCancelCount += 1 }
        cancelled.signal()
    }
}
