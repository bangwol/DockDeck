import Cocoa
import Combine
import SwiftUI
import XCTest

@testable import DockDeck

final class GitHubInboxTests: XCTestCase {
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
              [{"reason":"mention"},{"reason":"review_requested"}],
              [{"reason":"team_mention"},{"reason":"ci_activity"},{"reason":"subscribed"}]
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
            actionsRepository: "bangwol/DockDeck", observedAt: Date())
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
