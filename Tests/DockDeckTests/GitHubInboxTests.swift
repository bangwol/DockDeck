import Cocoa
import Combine
import SwiftUI
import XCTest

@testable import DockDeck

final class GitHubInboxTests: XCTestCase {
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
        configuration: GitHubInboxConfiguration, now: Date
    ) throws -> GitHubInboxSnapshot {
        snapshot
    }
}
