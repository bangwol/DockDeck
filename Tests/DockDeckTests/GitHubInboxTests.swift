import Cocoa
import Combine
import SwiftUI
import XCTest

@testable import DockDeck

final class GitHubInboxTests: XCTestCase {
    func testFiltersKeepAccountTotalsAndBoundCachedMessages() {
        let entries = (0..<150).map { index in
            GitHubInboxEntry(id: "\(index)", title: "Notification", repository: index % 2 == 0 ? "owner/one" : "owner/two",
                reason: index % 2 == 0 ? "team_mention" : "review_requested", updatedAt: nil)
        }
        let snapshot = GitHubInboxSnapshot(unreadCount: 150, mentionCount: 75, reviewRequestCount: 75,
            ciNotificationCount: 0, failedRunsLastSevenDays: nil, actionsRepository: nil,
            entries: entries, observedAt: Date())
        XCTAssertEqual(snapshot.entries.count, 100)
        XCTAssertEqual(snapshot.filteredEntries(reason: "mention").count, 50)
        XCTAssertEqual(snapshot.filteredEntries(repository: "owner/two", reason: "mention").count, 0)
        XCTAssertEqual(snapshot.filteredEntries(repository: "owner/two", reason: "review_requested").count, 50)
        XCTAssertEqual(snapshot.unreadCount, 150)
    }

    func testLiveClientUsesAuthenticatedGitHubSessionWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["DOCKDECK_LIVE_GITHUB_TEST"] == "1"
        else { throw XCTSkip("Set DOCKDECK_LIVE_GITHUB_TEST=1 to query GitHub") }
        let client = GitHubInboxClient()

        let first = try client.read(
            configuration: GitHubInboxConfiguration(), now: Date())
        let second = try client.read(
            configuration: GitHubInboxConfiguration(), now: Date())

        XCTAssertGreaterThanOrEqual(first.unreadCount, 0)
        XCTAssertGreaterThanOrEqual(second.observedAt, first.observedAt)
        XCTAssertGreaterThanOrEqual(client.minimumPollInterval, 0)
    }

    func testConfigurationNormalizesRepositoryAndRefreshInterval() {
        let configuration = GitHubInboxConfiguration(
            actionsRepository: "  bangwol/DockDeck  ", refreshInterval: 601)

        XCTAssertEqual(configuration.actionsRepository, "bangwol/DockDeck")
        XCTAssertEqual(configuration.refreshInterval, 600)
        XCTAssertNil(
            GitHubInboxConfiguration(actionsRepository: "invalid", refreshInterval: 1)
                .actionsRepository)
    }

    func testNotificationParserSummarizesPaginatedInbox() throws {
        let data = Data(
            """
            [
              [{"id":"1","reason":"mention","updated_at":"2026-09-03T10:00:00Z","subject":{"title":"Ping","url":"https://api.github.com/repos/bangwol/DockDeck/issues/12"},"repository":{"full_name":"bangwol/DockDeck"}},{"id":"2","reason":"review_requested","updated_at":"2026-09-02T10:00:00Z","subject":{"title":"Review DockDeck","url":"https://api.github.com/repos/bangwol/DockDeck/pulls/34"},"repository":{"full_name":"bangwol/DockDeck"}}],
              [{"id":"3","reason":"team_mention","updated_at":"2026-09-01T10:00:00Z","subject":{"title":"Team ping"},"repository":{"full_name":"openai/example"}},{"id":"4","reason":"ci_activity","updated_at":"2026-09-04T10:00:00Z","subject":{"title":"CI failed"},"repository":{"full_name":"bangwol/DockDeck"}},{"reason":"subscribed"}]
            ]
            """.utf8)

        let snapshot = try GitHubInboxParser.parseNotifications(
            data, failedRuns: 2, repository: "bangwol/DockDeck",
            observedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(snapshot.unreadCount, 5)
        XCTAssertEqual(snapshot.mentionCount, 2)
        XCTAssertEqual(snapshot.reviewRequestCount, 1)
        XCTAssertEqual(snapshot.ciNotificationCount, 1)
        XCTAssertEqual(snapshot.failedRunsLastSevenDays, 2)
        XCTAssertEqual(
            snapshot.entries.map(\.title),
            ["Review DockDeck", "Ping", "Team ping", "CI failed"])
        XCTAssertEqual(snapshot.entries.first?.reasonLabel, "REVIEW")
        XCTAssertEqual(snapshot.entries.first?.repositoryName, "DockDeck")
        XCTAssertEqual(
            snapshot.entries.first?.webURL?.absoluteString,
            "https://github.com/bangwol/DockDeck/pull/34")
    }

    func testNotificationURLResolverRejectsLookalikesAndCredentials() {
        for (path, resolvedPath) in [
            ("issues/12", "/issues/12"), ("actions/runs/42", "/actions/runs/42"),
            ("commits/a-b_c.d", "/commit/a-b_c.d"), ("releases/1", "/releases"),
            ("issues/bad%2Fname", ""), ("issues/bad%3Fname", ""),
        ] {
            XCTAssertEqual(
                GitHubNotificationURLResolver.resolve(
                    apiURL: "https://api.github.com/repos/bangwol/DockDeck/\(path)",
                    repository: "bangwol/DockDeck")?.absoluteString,
                "https://github.com/bangwol/DockDeck\(resolvedPath)", path)
        }
        XCTAssertEqual(
            GitHubNotificationURLResolver.resolve(
                apiURL: "https://api.github.com/repos/bangwol/DockDeck/commits/abc123",
                repository: "bangwol/DockDeck")?.absoluteString,
            "https://github.com/bangwol/DockDeck/commit/abc123")
        XCTAssertEqual(
            GitHubNotificationURLResolver.resolve(
                apiURL: "https://api.github.com.evil.test/repos/bangwol/DockDeck/issues/1",
                repository: "bangwol/DockDeck")?.absoluteString,
            "https://github.com/bangwol/DockDeck")
        XCTAssertEqual(
            GitHubNotificationURLResolver.resolve(
                apiURL: "https://user:secret@api.github.com/repos/bangwol/DockDeck/issues/1",
                repository: "bangwol/DockDeck")?.absoluteString,
            "https://github.com/bangwol/DockDeck")
    }

    func testIncludedResponseParserReadsHeadersAndBody() throws {
        let response = try GitHubIncludedResponseParser.parse(Data(
            """
            HTTP/2.0 200 OK\r
            Etag: "abc"\r
            X-Poll-Interval: 90\r
            \r
            [{"id":"1"}]
            """.utf8))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["etag"], "\"abc\"")
        XCTAssertEqual(response.headers["x-poll-interval"], "90")
        XCTAssertEqual(String(data: response.body, encoding: .utf8), "[{\"id\":\"1\"}]")
    }

    func testIncludedResponseParserAcceptsNotModifiedWithoutBody() throws {
        let response = try GitHubIncludedResponseParser.parse(Data(
            "HTTP/2.0 304 Not Modified\r\nX-Poll-Interval: 120\r\n\r\n".utf8))

        XCTAssertEqual(response.statusCode, 304)
        XCTAssertEqual(response.headers["x-poll-interval"], "120")
        XCTAssertTrue(response.body.isEmpty)
    }

    func testFailedRunParserKeepsOnlyRecentFailures() throws {
        let data = Data(
            """
            [
              {"conclusion":"failure","createdAt":"2026-09-02T00:00:00Z"},
              {"conclusion":"timed_out","createdAt":"2026-09-01T00:00:00Z"},
              {"conclusion":"success","createdAt":"2026-09-02T00:00:00Z"},
              {"conclusion":"failure","createdAt":"2026-08-01T00:00:00Z"}
            ]
            """.utf8)

        let count = try GitHubInboxParser.parseFailedRuns(
            data, since: ISO8601DateFormatter().date(from: "2026-08-28T00:00:00Z")!)

        XCTAssertEqual(count, 2)
    }

    func testClientQueriesCompletedRunsAndReusesConditionalNotifications() throws {
        let cli = try makeCLI(#"""
            if [ "$1" = api ]; then
                if [ -f fetched ]; then
                    case "$*" in *'If-None-Match: "inbox"'*) ;; *) exit 2 ;; esac
                    printf 'HTTP/2.0 304 Not Modified\r\nX-Poll-Interval: 90\r\n\r\n'
                    exit 1
                fi
                touch fetched
                printf 'HTTP/2.0 200 OK\r\nETag: "inbox"\r\nX-Poll-Interval: 90\r\n\r\n'
                printf '[{"id":"1","reason":"mention","subject":{"title":"Keep this notification"},"repository":{"full_name":"owner/repo"}}]'
            else
                [ "$*" = 'run list --repo owner/repo --limit 100 --status completed --json conclusion,createdAt' ] || exit 2
                printf '[{"conclusion":"failure","createdAt":"2026-09-02T00:00:00Z"},{"conclusion":"timed_out","createdAt":"2026-09-02T00:00:00Z"},{"conclusion":"startup_failure","createdAt":"2026-09-02T00:00:00Z"},{"conclusion":"action_required","createdAt":"2026-09-02T00:00:00Z"},{"conclusion":"success","createdAt":"2026-09-02T00:00:00Z"},{"conclusion":"failure","createdAt":"2026-08-01T00:00:00Z"}]'
            fi
            """#)
        defer { try? FileManager.default.removeItem(at: cli.deletingLastPathComponent()) }
        let client = GitHubInboxClient(broker: GitHubCLIRequestBroker(), executableLocator: { cli })
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-03T00:00:00Z"))
        for _ in 0..<2 {
            let snapshot = try client.read(
                configuration: GitHubInboxConfiguration(actionsRepository: "owner/repo"), now: now)
            XCTAssertEqual(snapshot.unreadCount, 1)
            XCTAssertEqual(snapshot.entries.first?.title, "Keep this notification")
            XCTAssertEqual(snapshot.failedRunsLastSevenDays, 4)
            XCTAssertNil(snapshot.actionsError)
            XCTAssertEqual(client.minimumPollInterval, 90)
        }
    }

    func testActionsFailuresKeepNotificationsAndExplainPartialFailure() throws {
        for (command, message) in [
            ("exit 1", "Actions check failed; check repository access and GitHub CLI sign-in"),
            ("printf invalid", "Actions returned an invalid response"),
            ("/bin/dd if=/dev/zero bs=1048576 count=2 2>/dev/null", "Actions response exceeded its size limit"),
            ("/bin/sleep 9", "Actions check timed out"),
        ] {
            let cli = try makeCLI(#"""
                if [ "$1" = api ]; then
                    printf 'HTTP/2.0 200 OK\r\n\r\n[{"id":"1","reason":"mention","subject":{"title":"Notification survives"},"repository":{"full_name":"owner/repo"}}]'
                else
                """# + "\n" + command + "\nfi\n")
            defer { try? FileManager.default.removeItem(at: cli.deletingLastPathComponent()) }
            let client = GitHubInboxClient(broker: GitHubCLIRequestBroker(), executableLocator: { cli })
            let snapshot = try client.read(
                configuration: GitHubInboxConfiguration(actionsRepository: "owner/repo"), now: Date())
            XCTAssertEqual(snapshot.unreadCount, 1)
            XCTAssertEqual(snapshot.entries.first?.title, "Notification survives")
            XCTAssertNil(snapshot.failedRunsLastSevenDays)
            XCTAssertEqual(snapshot.actionsError, message)
            let store = GitHubInboxStore(initialSnapshot: snapshot)
            let view = GitHubInboxPanelView(store: store, theme: Theme.theme(id: ""))
            XCTAssertTrue(view.helpText(snapshot).contains(message))
            XCTAssertFalse(view.helpText(snapshot).contains("CI notifications"))
        }
    }

    func testConditionalRequestWaitsForSharedBrokerAndCancelsWithoutLaunching() throws {
        let cli = try makeCLI(#"""
            if [ "$1" = hold ]; then
                touch held
                while [ ! -f release ]; do sleep 0.01; done
            else
                touch inbox-started
                printf 'HTTP/2.0 200 OK\r\n\r\n[]'
            fi
            """#)
        let directory = cli.deletingLastPathComponent()
        let broker = GitHubCLIRequestBroker()
        let holderFinished = expectation(description: "Shared request released")
        DispatchQueue.global().async {
            defer { holderFinished.fulfill() }
            do {
                _ = try broker.run(
                    executableURL: cli, arguments: ["hold"], currentDirectoryURL: directory,
                    environment: [:], timeout: 4)
            } catch { XCTFail("Shared request failed: \(error)") }
        }
        defer {
            try? Data().write(to: directory.appendingPathComponent("release"))
            wait(for: [holderFinished], timeout: 5)
            try? FileManager.default.removeItem(at: directory)
        }
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("held").path),
            Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("held").path))
        let requested = expectation(description: "Inbox request queued")
        let cancelled = expectation(description: "Queued inbox cancelled")
        let cancellation = Progress(totalUnitCount: 1)
        let client = GitHubInboxClient(broker: broker, executableLocator: {
            requested.fulfill()
            return cli
        })
        DispatchQueue.global().async {
            defer { cancelled.fulfill() }
            do {
                _ = try client.read(configuration: .init(), now: Date(), cancellation: cancellation)
                XCTFail("Queued request should be cancelled")
            } catch { XCTAssertEqual(error as? BoundedProcessError, .cancelled) }
        }
        wait(for: [requested], timeout: 2)
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("inbox-started").path))
        cancellation.cancel()
        wait(for: [cancelled], timeout: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("inbox-started").path))
    }

    private func makeCLI(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDeckInbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cli = directory.appendingPathComponent("gh")
        try Data(("#!/bin/sh\nset -eu\ncd -- \"$(dirname \"$0\")\"\n" + script + "\n").utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        return cli
    }

    func testStoreRefreshesAndCompactPanelRenders() throws {
        let snapshot = GitHubInboxSnapshot(
            unreadCount: 12, mentionCount: 2, reviewRequestCount: 3,
            ciNotificationCount: 1, failedRunsLastSevenDays: 4,
            actionsRepository: "bangwol/DockDeck",
            entries: [
                GitHubInboxEntry(
                    id: "1", title: "Review compact layout",
                    repository: "bangwol/DockDeck", reason: "review_requested",
                    updatedAt: Date())
            ],
            observedAt: Date())
        let store = GitHubInboxStore(
            configuration: GitHubInboxConfiguration(),
            reader: FakeGitHubInboxReader(snapshot: snapshot))
        let loaded = expectation(description: "GitHub Inbox loaded")
        var fulfilled = false
        let cancellable = store.$snapshot.sink {
            guard !fulfilled, $0 == snapshot else { return }
            fulfilled = true
            loaded.fulfill()
        }
        defer {
            store.stop()
            cancellable.cancel()
        }

        store.start()
        assertCadenceKeepsPollingDeadline(store, interval: GitHubInboxConfiguration.defaultRefreshInterval,
            backgroundMultiplier: 3, deadline: { store.nextRefreshAt })
        wait(for: [loaded], timeout: 2)

        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: GitHubInboxPanelView(store: store, theme: Theme.theme(id: ""))
                .frame(width: size.width, height: size.height))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)

        let detailSize = NSSize(width: 480, height: 180)
        let detail = NSHostingView(
            rootView: GitHubInboxDetailView(store: store, theme: Theme.theme(id: ""))
                .frame(width: detailSize.width, height: detailSize.height))
        detail.frame = NSRect(origin: .zero, size: detailSize)
        detail.layoutSubtreeIfNeeded()
        let detailBitmap = try XCTUnwrap(
            detail.bitmapImageRepForCachingDisplay(in: detail.bounds))
        detail.cacheDisplay(in: detail.bounds, to: detailBitmap)
        XCTAssertGreaterThan(detailBitmap.pixelsWide, 0)
    }
}
private struct FakeGitHubInboxReader: GitHubInboxReading {
    let snapshot: GitHubInboxSnapshot

    func read(
        configuration: GitHubInboxConfiguration, now: Date, cancellation: Progress?
    ) throws -> GitHubInboxSnapshot {
        snapshot
    }
}
