import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class ProjectPulseTests: XCTestCase {
    func testConfigurationNormalizesAbsolutePathAndRefreshInterval() {
        let configuration = ProjectPulseConfiguration(
            repositoryPath: "/tmp/../tmp/example",
            includesGitHubActions: true,
            refreshInterval: 77)

        XCTAssertEqual(configuration.repositoryPath, "/tmp/example")
        XCTAssertTrue(configuration.includesGitHubActions)
        XCTAssertEqual(configuration.refreshInterval, 60)
        XCTAssertNil(
            ProjectPulseConfiguration(repositoryPath: "relative/repo").repositoryPath)
    }

    func testGitPorcelainParserCountsChangesAndBranchSync() throws {
        let records = [
            "# branch.oid abcdef1234567890",
            "# branch.head feature/pulse",
            "# branch.upstream origin/feature/pulse",
            "# branch.ab +2 -1",
            "1 M. N... 100644 100644 100644 a b staged.swift",
            "1 .M N... 100644 100644 100644 a b modified.swift",
            "1 MM N... 100644 100644 100644 a b both.swift",
            "u UU N... 100644 100644 100644 100644 a b c conflict.swift",
            "? untracked.swift",
        ]
        let data = Data((records.joined(separator: "\0") + "\0").utf8)

        let snapshot = try GitPorcelainV2Parser.parse(
            data, repositoryName: "DockDeck")

        XCTAssertEqual(snapshot.repositoryName, "DockDeck")
        XCTAssertEqual(snapshot.branch, "feature/pulse")
        XCTAssertEqual(snapshot.stagedCount, 2)
        XCTAssertEqual(snapshot.modifiedCount, 2)
        XCTAssertEqual(snapshot.untrackedCount, 1)
        XCTAssertEqual(snapshot.conflictCount, 1)
        XCTAssertEqual(snapshot.aheadCount, 2)
        XCTAssertEqual(snapshot.behindCount, 1)
        XCTAssertEqual(snapshot.changeCount, 6)
    }

    func testGitPorcelainParserUsesShortObjectIDWhenDetached() throws {
        let data = Data(
            "# branch.oid abcdef1234567890\0# branch.head (detached)\0".utf8)

        let snapshot = try GitPorcelainV2Parser.parse(data, repositoryName: "Repo")

        XCTAssertEqual(snapshot.branch, "abcdef12")
    }

    func testGitHubRunParserMapsLatestRunState() throws {
        let success = try XCTUnwrap(
            GitHubRunParser.parse(
                Data(
                    #"[{"status":"completed","conclusion":"success","name":"CI","displayTitle":"Build"}]"#
                        .utf8)))
        let running = try XCTUnwrap(
            GitHubRunParser.parse(
                Data(
                    #"[{"status":"in_progress","conclusion":null,"name":"CI","displayTitle":""}]"#
                        .utf8)))

        XCTAssertEqual(success.state, .success)
        XCTAssertEqual(success.title, "Build")
        XCTAssertEqual(running.state, .running)
        XCTAssertEqual(running.title, "CI")
        XCTAssertNil(try GitHubRunParser.parse(Data("[]".utf8)))
    }

    func testStorePublishesReaderSnapshot() {
        let snapshot = fixtureSnapshot()
        let store = ProjectPulseStore(
            configuration: ProjectPulseConfiguration(repositoryPath: "/tmp"),
            reader: FakeProjectPulseReader(snapshot: snapshot))
        let completed = expectation(description: "Project status completed")
        var fulfilled = false
        let cancellable = store.$status.sink { status in
            guard !fulfilled, status == .ready else { return }
            fulfilled = true
            completed.fulfill()
        }

        store.start()
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(store.snapshot, snapshot)
        cancellable.cancel()
        store.stop()
    }

    func testReaderReadsTemporaryGitRepository() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("DockDeckProjectPulse-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let git = try XCTUnwrap(ProjectPulseBinaryLocator.git())
        _ = try ProjectPulseCommand.run(
            executableURL: git,
            arguments: ["init", "--quiet"],
            currentDirectoryURL: directory)
        try Data("untracked\n".utf8).write(
            to: directory.appendingPathComponent("note.txt"))

        let snapshot = try ProjectPulseReader().read(
            configuration: ProjectPulseConfiguration(repositoryPath: directory.path))

        XCTAssertEqual(snapshot.git.repositoryName, directory.lastPathComponent)
        XCTAssertEqual(snapshot.git.untrackedCount, 1)
        XCTAssertEqual(snapshot.git.changeCount, 1)
        XCTAssertNil(snapshot.workflow)
    }

    func testPanelRendersAtCompactSize() throws {
        let store = ProjectPulseStore(
            configuration: ProjectPulseConfiguration(repositoryPath: "/tmp"),
            reader: FakeProjectPulseReader(snapshot: fixtureSnapshot()),
            initialSnapshot: fixtureSnapshot())
        let size = NSSize(width: 214, height: 59)
        let view = NSHostingView(
            rootView: ProjectPulsePanelView(store: store, theme: Theme.theme(id: "")))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    private func fixtureSnapshot() -> ProjectPulseSnapshot {
        ProjectPulseSnapshot(
            git: ProjectGitSnapshot(
                repositoryName: "DockDeck",
                branch: "main",
                stagedCount: 1,
                modifiedCount: 2,
                untrackedCount: 0,
                conflictCount: 0,
                aheadCount: 1,
                behindCount: 0),
            workflow: ProjectWorkflowSnapshot(state: .success, title: "Build"))
    }
}

private struct FakeProjectPulseReader: ProjectPulseReading {
    let snapshot: ProjectPulseSnapshot

    func read(configuration: ProjectPulseConfiguration) throws -> ProjectPulseSnapshot {
        snapshot
    }
}
