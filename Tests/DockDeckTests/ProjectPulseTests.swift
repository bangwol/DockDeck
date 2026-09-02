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

    func testConfigurationNormalizesGitHubSelectionAndMigratesLocalStorage() throws {
        let github = ProjectPulseConfiguration(
            source: .github,
            repositoryPath: "/tmp/local-copy",
            githubRepository: " bangwol/DockDeck ")

        XCTAssertEqual(github.source, .github)
        XCTAssertEqual(github.githubScope, .repository)
        XCTAssertEqual(github.githubRepository, "bangwol/DockDeck")
        XCTAssertEqual(github.repositoryPath, "/tmp/local-copy")
        XCTAssertTrue(github.isConfigured)
        XCTAssertNil(
            ProjectPulseConfiguration(
                source: .github, githubRepository: "owner/repo/extra"
            ).githubRepository)
        XCTAssertNil(
            ProjectPulseConfiguration(
                source: .github, githubRepository: "owner/."
            ).githubRepository)

        let legacy = Data(
            #"{"repositoryPath":"/tmp/legacy","includesGitHubActions":true,"refreshInterval":60}"#
                .utf8)
        let decoded = try JSONDecoder().decode(ProjectPulseConfiguration.self, from: legacy)

        XCTAssertEqual(decoded.source, .local)
        XCTAssertEqual(decoded.githubScope, .repository)
        XCTAssertEqual(decoded.repositoryPath, "/tmp/legacy")
        XCTAssertNil(decoded.githubRepository)
        XCTAssertTrue(decoded.isConfigured)

        let activity = ProjectPulseConfiguration(
            source: .github, githubScope: .activity, refreshInterval: 30)
        XCTAssertTrue(activity.isConfigured)
        XCTAssertEqual(activity.refreshInterval, 300)
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

    func testGitHubProjectParserReadsCompactActivity() throws {
        let data = Data(
            #"{"data":{"repository":{"nameWithOwner":"bangwol/DockDeck","isPrivate":false,"pushedAt":"2026-09-02T08:36:22Z","defaultBranchRef":{"name":"main","target":{"abbreviatedOid":"6084895","history":{"totalCount":69}}},"pullRequests":{"totalCount":2},"issues":{"totalCount":4},"stargazerCount":8,"forkCount":3}}}"#
                .utf8)

        let repository = try GitHubProjectParser.parse(data)

        XCTAssertEqual(repository.nameWithOwner, "bangwol/DockDeck")
        XCTAssertEqual(repository.shortName, "DockDeck")
        XCTAssertEqual(repository.defaultBranch, "main")
        XCTAssertEqual(repository.headOID, "6084895")
        XCTAssertEqual(repository.commitsLastSevenDays, 69)
        XCTAssertEqual(repository.openPullRequests, 2)
        XCTAssertEqual(repository.openIssues, 4)
        XCTAssertEqual(repository.stargazerCount, 8)
        XCTAssertEqual(repository.forkCount, 3)
        XCTAssertNotNil(repository.pushedAt)
    }

    func testGitHubActivityParserReadsViewerContributions() throws {
        let data = Data(
            #"{"data":{"viewer":{"login":"bangwol","contributionsCollection":{"contributionCalendar":{"totalContributions":320},"totalCommitContributions":69,"totalPullRequestContributions":1,"totalPullRequestReviewContributions":2,"totalIssueContributions":3,"totalRepositoriesWithContributedCommits":4,"restrictedContributionsCount":248}}}}"#
                .utf8)

        let activity = try GitHubActivityParser.parse(data)

        XCTAssertEqual(activity.login, "bangwol")
        XCTAssertEqual(activity.totalContributions, 320)
        XCTAssertEqual(activity.commitContributions, 69)
        XCTAssertEqual(activity.pullRequestContributions, 1)
        XCTAssertEqual(activity.reviewContributions, 2)
        XCTAssertEqual(activity.issueContributions, 3)
        XCTAssertEqual(activity.repositoriesWithCommits, 4)
        XCTAssertEqual(activity.restrictedContributions, 248)
    }

    func testGitHubRepositoryListParserFiltersInvalidAndDuplicateNames() throws {
        let data = Data(
            #"[{"full_name":"bangwol/DockDeck","private":false,"archived":false,"pushed_at":"2026-09-02T08:36:22Z"},{"full_name":"bangwol/DockDeck","private":false,"archived":false,"pushed_at":null},{"full_name":"bad/name/extra","private":true,"archived":false,"pushed_at":null},{"full_name":"bangwol/archive","private":true,"archived":true,"pushed_at":null}]"#
                .utf8)

        let repositories = try GitHubRepositoryListParser.parse(data)

        XCTAssertEqual(repositories.map(\.nameWithOwner), ["bangwol/DockDeck", "bangwol/archive"])
        XCTAssertFalse(repositories[0].isPrivate)
        XCTAssertTrue(repositories[1].isPrivate)
        XCTAssertTrue(repositories[1].isArchived)
    }

    func testGitHubRepositoryCatalogPublishesLoadedOptions() {
        let option = GitHubRepositoryOption(
            nameWithOwner: "bangwol/DockDeck",
            isPrivate: false,
            isArchived: false,
            pushedAt: nil)
        let catalog = GitHubRepositoryCatalog(
            listing: FakeGitHubRepositoryListing(repositories: [option]))
        let completed = expectation(description: "Repository list loaded")
        var fulfilled = false
        let cancellable = catalog.$status.sink { status in
            guard !fulfilled, status == .ready else { return }
            fulfilled = true
            completed.fulfill()
        }

        catalog.load()
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(catalog.repositories, [option])
        cancellable.cancel()
    }

    func testReaderBuildsRemoteSnapshotWithoutLocalRepository() throws {
        let github = fixtureGitHubSnapshot()
        let workflow = ProjectWorkflowSnapshot(state: .success, title: "Build")
        let reader = ProjectPulseReader(
            github: FakeGitHubProjectReader(
                result: GitHubProjectResult(repository: github, workflow: workflow)))

        let snapshot = try reader.read(
            configuration: ProjectPulseConfiguration(
                source: .github,
                githubRepository: github.nameWithOwner,
                includesGitHubActions: true))

        XCTAssertEqual(snapshot.git.repositoryName, "DockDeck")
        XCTAssertEqual(snapshot.git.branch, "main")
        XCTAssertEqual(snapshot.github, github)
        XCTAssertEqual(snapshot.workflow, workflow)
    }

    func testReaderBuildsGitHubActivitySnapshot() throws {
        let activity = fixtureGitHubActivitySnapshot()
        let reader = ProjectPulseReader(
            github: FakeGitHubProjectReader(activity: activity))

        let snapshot = try reader.read(
            configuration: ProjectPulseConfiguration(
                source: .github, githubScope: .activity))

        XCTAssertEqual(snapshot.git.repositoryName, "@bangwol")
        XCTAssertNil(snapshot.github)
        XCTAssertEqual(snapshot.githubActivity, activity)
        XCTAssertNil(snapshot.workflow)
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

    func testStoreClearsRepositorySnapshotWhenSwitchingGitHubScope() {
        let repository = fixtureGitHubSnapshot()
        let snapshot = ProjectPulseSnapshot(
            git: ProjectGitSnapshot(
                repositoryName: repository.shortName,
                branch: repository.defaultBranch,
                stagedCount: 0,
                modifiedCount: 0,
                untrackedCount: 0,
                conflictCount: 0,
                aheadCount: 0,
                behindCount: 0),
            github: repository,
            workflow: nil)
        let store = ProjectPulseStore(
            configuration: ProjectPulseConfiguration(
                source: .github,
                githubRepository: repository.nameWithOwner),
            reader: FakeProjectPulseReader(snapshot: snapshot),
            initialSnapshot: snapshot)

        store.updateConfiguration(
            ProjectPulseConfiguration(source: .github, githubScope: .activity))

        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.status, .loading)
    }

    func testCommandRejectsCombinedOutputAboveLimit() throws {
        XCTAssertThrowsError(
            try ProjectPulseCommand.run(
                executableURL: URL(fileURLWithPath: "/bin/dd"),
                arguments: [
                    "if=/dev/zero",
                    "bs=\(ProjectPulseCommand.maximumOutputBytes + 1)",
                    "count=1",
                ],
                currentDirectoryURL: FileManager.default.temporaryDirectory)
        ) { error in
            XCTAssertEqual(error as? ProjectPulseError, .outputTooLarge)
        }
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

    func testPanelRendersGitHubActivityAtCompactSize() throws {
        let github = fixtureGitHubSnapshot()
        let snapshot = ProjectPulseSnapshot(
            git: ProjectGitSnapshot(
                repositoryName: github.shortName,
                branch: github.defaultBranch,
                stagedCount: 0,
                modifiedCount: 0,
                untrackedCount: 0,
                conflictCount: 0,
                aheadCount: 0,
                behindCount: 0),
            github: github,
            workflow: ProjectWorkflowSnapshot(state: .running, title: "Test"))
        let store = ProjectPulseStore(
            configuration: ProjectPulseConfiguration(
                source: .github, githubRepository: github.nameWithOwner),
            reader: FakeProjectPulseReader(snapshot: snapshot),
            initialSnapshot: snapshot)
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

    func testPanelRendersAllGitHubActivityAtCompactSize() throws {
        let activity = fixtureGitHubActivitySnapshot()
        let snapshot = ProjectPulseSnapshot(
            git: ProjectGitSnapshot(
                repositoryName: "@\(activity.login)",
                branch: "7 days",
                stagedCount: 0,
                modifiedCount: 0,
                untrackedCount: 0,
                conflictCount: 0,
                aheadCount: 0,
                behindCount: 0),
            githubActivity: activity,
            workflow: nil)
        let store = ProjectPulseStore(
            configuration: ProjectPulseConfiguration(
                source: .github, githubScope: .activity),
            reader: FakeProjectPulseReader(snapshot: snapshot),
            initialSnapshot: snapshot)
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

    private func fixtureGitHubSnapshot() -> ProjectGitHubSnapshot {
        ProjectGitHubSnapshot(
            nameWithOwner: "bangwol/DockDeck",
            defaultBranch: "main",
            headOID: "6084895",
            commitsLastSevenDays: 69,
            openPullRequests: 2,
            openIssues: 4,
            stargazerCount: 8,
            forkCount: 3,
            isPrivate: false,
            pushedAt: Date(timeIntervalSince1970: 1_756_800_000))
    }

    private func fixtureGitHubActivitySnapshot() -> ProjectGitHubActivitySnapshot {
        ProjectGitHubActivitySnapshot(
            login: "bangwol",
            totalContributions: 320,
            commitContributions: 69,
            pullRequestContributions: 1,
            reviewContributions: 2,
            issueContributions: 3,
            repositoriesWithCommits: 4,
            restrictedContributions: 248)
    }
}

private struct FakeProjectPulseReader: ProjectPulseReading {
    let snapshot: ProjectPulseSnapshot

    func read(configuration: ProjectPulseConfiguration) throws -> ProjectPulseSnapshot {
        snapshot
    }
}

private struct FakeGitHubProjectReader: GitHubProjectReading {
    let result: GitHubProjectResult?
    let activity: ProjectGitHubActivitySnapshot?

    init(result: GitHubProjectResult) {
        self.result = result
        activity = nil
    }

    init(activity: ProjectGitHubActivitySnapshot) {
        result = nil
        self.activity = activity
    }

    func readRepository(
        _ nameWithOwner: String,
        includesWorkflow: Bool,
        now: Date
    ) throws -> GitHubProjectResult {
        guard let result else { throw ProjectPulseError.githubUnavailable }
        return result
    }

    func readActivity(now: Date) throws -> ProjectGitHubActivitySnapshot {
        guard let activity else { throw ProjectPulseError.githubUnavailable }
        return activity
    }

    func readWorkflow(
        repository: String?,
        currentDirectoryURL: URL
    ) -> ProjectWorkflowSnapshot {
        result?.workflow
            ?? ProjectWorkflowSnapshot(state: .neutral, title: "No workflow runs")
    }
}

private struct FakeGitHubRepositoryListing: GitHubRepositoryListing {
    let repositories: [GitHubRepositoryOption]

    func listRepositories() throws -> [GitHubRepositoryOption] {
        repositories
    }
}
