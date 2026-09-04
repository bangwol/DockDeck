import Combine
import Foundation

final class GitHubCLIRequestBroker {
    static let shared = GitHubCLIRequestBroker()

    private struct CacheEntry {
        let data: Data
        let expiresAt: Date
    }

    private let lock = NSLock()
    private var cache: [String: CacheEntry] = [:]

    private init() {}

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String],
        cacheKey: String? = nil,
        cacheDuration: TimeInterval = 0
    ) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        cache = cache.filter { $0.value.expiresAt > now }
        if let cacheKey, let cached = cache[cacheKey] { return cached.data }

        let data = try BoundedProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environmentAdditions: environment)
        if let cacheKey, cacheDuration > 0 {
            cache[cacheKey] = CacheEntry(
                data: data, expiresAt: now.addingTimeInterval(cacheDuration))
        }
        return data
    }
}

struct ProjectGitHubSnapshot: Equatable {
    let nameWithOwner: String
    let defaultBranch: String
    let headOID: String?
    let commitsLastSevenDays: Int
    let openPullRequests: Int
    let openIssues: Int
    let stargazerCount: Int
    let forkCount: Int
    let isPrivate: Bool
    let pushedAt: Date?

    var shortName: String {
        nameWithOwner.split(separator: "/", maxSplits: 1).last.map(String.init)
            ?? nameWithOwner
    }
}

struct ProjectGitHubActivitySnapshot: Equatable {
    let login: String
    let totalContributions: Int
    let commitContributions: Int
    let pullRequestContributions: Int
    let reviewContributions: Int
    let issueContributions: Int
    let repositoriesWithCommits: Int
    let restrictedContributions: Int
}

struct GitHubProjectResult: Equatable {
    let repository: ProjectGitHubSnapshot
    let workflow: ProjectWorkflowSnapshot?
}

struct GitHubRepositoryOption: Identifiable, Equatable {
    let nameWithOwner: String
    let isPrivate: Bool
    let isArchived: Bool
    let pushedAt: Date?

    var id: String { nameWithOwner }
}

protocol GitHubProjectReading {
    func readRepository(
        _ nameWithOwner: String,
        includesWorkflow: Bool,
        now: Date
    ) throws -> GitHubProjectResult

    func readActivity(now: Date) throws -> ProjectGitHubActivitySnapshot

    func readWorkflow(
        repository: String?,
        currentDirectoryURL: URL
    ) -> ProjectWorkflowSnapshot
}

protocol GitHubRepositoryListing {
    func listRepositories() throws -> [GitHubRepositoryOption]
}

struct GitHubProjectClient: GitHubProjectReading, GitHubRepositoryListing {
    private static let environment = [
        "GH_PROMPT_DISABLED": "1",
        "NO_COLOR": "1",
        "PAGER": "cat",
    ]

    private static let repositoryQuery = """
        query($owner:String!,$name:String!,$since:GitTimestamp!){
          repository(owner:$owner,name:$name){
            nameWithOwner
            isPrivate
            pushedAt
            defaultBranchRef{
              name
              target{
                ... on Commit{
                  abbreviatedOid
                  history(since:$since){totalCount}
                }
              }
            }
            pullRequests(states:OPEN){totalCount}
            issues(states:OPEN){totalCount}
            stargazerCount
            forkCount
          }
        }
        """

    private static let activityQuery = """
        query($from:DateTime!,$to:DateTime!){
          viewer{
            login
            contributionsCollection(from:$from,to:$to){
              contributionCalendar{totalContributions}
              totalCommitContributions
              totalPullRequestContributions
              totalPullRequestReviewContributions
              totalIssueContributions
              totalRepositoriesWithContributedCommits
              restrictedContributionsCount
            }
          }
        }
        """

    func readRepository(
        _ nameWithOwner: String,
        includesWorkflow: Bool,
        now: Date
    ) throws -> GitHubProjectResult {
        guard let repository = ProjectPulseConfiguration.normalizedGitHubRepository(
            nameWithOwner)
        else { throw ProjectPulseError.githubUnavailable }
        guard let gh = ProjectPulseBinaryLocator.githubCLI() else {
            throw ProjectPulseError.githubCLIUnavailable
        }
        let parts = repository.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw ProjectPulseError.githubUnavailable }
        let since = ISO8601DateFormatter().string(
            from: now.addingTimeInterval(-7 * 24 * 60 * 60))

        let output: Data
        do {
            output = try GitHubCLIRequestBroker.shared.run(
                executableURL: gh,
                arguments: [
                    "api", "graphql",
                    "-f", "query=\(Self.repositoryQuery)",
                    "-F", "owner=\(parts[0])",
                    "-F", "name=\(parts[1])",
                    "-F", "since=\(since)",
                ],
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
                environment: Self.environment,
                cacheKey: "repository:\(repository)", cacheDuration: 60)
        } catch let error as ProjectPulseError
            where error == .commandTimedOut || error == .outputTooLarge
        {
            throw error
        } catch {
            throw ProjectPulseError.githubUnavailable
        }

        let snapshot = try GitHubProjectParser.parse(output)
        let workflow = includesWorkflow
            ? readWorkflow(
                repository: repository,
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser)
            : nil
        return GitHubProjectResult(repository: snapshot, workflow: workflow)
    }

    func readActivity(now: Date) throws -> ProjectGitHubActivitySnapshot {
        guard let gh = ProjectPulseBinaryLocator.githubCLI() else {
            throw ProjectPulseError.githubCLIUnavailable
        }
        let formatter = ISO8601DateFormatter()
        let from = formatter.string(from: now.addingTimeInterval(-7 * 24 * 60 * 60))
        let to = formatter.string(from: now)
        let output: Data
        do {
            output = try GitHubCLIRequestBroker.shared.run(
                executableURL: gh,
                arguments: [
                    "api", "graphql",
                    "-f", "query=\(Self.activityQuery)",
                    "-F", "from=\(from)",
                    "-F", "to=\(to)",
                ],
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
                environment: Self.environment,
                cacheKey: "activity", cacheDuration: 60)
        } catch let error as ProjectPulseError
            where error == .commandTimedOut || error == .outputTooLarge
        {
            throw error
        } catch {
            throw ProjectPulseError.githubUnavailable
        }
        return try GitHubActivityParser.parse(output)
    }

    func readWorkflow(
        repository: String?,
        currentDirectoryURL: URL
    ) -> ProjectWorkflowSnapshot {
        guard let gh = ProjectPulseBinaryLocator.githubCLI() else {
            return ProjectWorkflowSnapshot(state: .unavailable, title: "Install gh for Actions")
        }
        var arguments = ["run", "list"]
        if let repository { arguments += ["--repo", repository] }
        arguments += [
            "--limit", "1", "--json", "status,conclusion,name,displayTitle",
        ]
        do {
            let output = try GitHubCLIRequestBroker.shared.run(
                executableURL: gh,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                environment: Self.environment,
                cacheKey: "workflow:\(repository ?? currentDirectoryURL.path)",
                cacheDuration: 30)
            return try GitHubRunParser.parse(output)
                ?? ProjectWorkflowSnapshot(state: .neutral, title: "No workflow runs")
        } catch {
            return ProjectWorkflowSnapshot(state: .unavailable, title: "Actions unavailable")
        }
    }

    func listRepositories() throws -> [GitHubRepositoryOption] {
        guard let gh = ProjectPulseBinaryLocator.githubCLI() else {
            throw ProjectPulseError.githubCLIUnavailable
        }
        let output: Data
        do {
            output = try GitHubCLIRequestBroker.shared.run(
                executableURL: gh,
                arguments: [
                    "api", "-X", "GET", "user/repos",
                    "-f", "affiliation=owner,collaborator,organization_member",
                    "-f", "sort=pushed",
                    "-f", "direction=desc",
                    "-F", "per_page=100",
                ],
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
                environment: Self.environment,
                cacheKey: "repositories", cacheDuration: 5 * 60)
        } catch let error as ProjectPulseError
            where error == .commandTimedOut || error == .outputTooLarge
        {
            throw error
        } catch {
            throw ProjectPulseError.githubUnavailable
        }
        return try GitHubRepositoryListParser.parse(output)
    }
}

enum GitHubActivityParser {
    private struct Response: Decodable {
        let data: Payload?
    }

    private struct Payload: Decodable {
        let viewer: Viewer?
    }

    private struct Viewer: Decodable {
        let login: String
        let contributionsCollection: Contributions
    }

    private struct Contributions: Decodable {
        let contributionCalendar: Calendar
        let totalCommitContributions: Int
        let totalPullRequestContributions: Int
        let totalPullRequestReviewContributions: Int
        let totalIssueContributions: Int
        let totalRepositoriesWithContributedCommits: Int
        let restrictedContributionsCount: Int
    }

    private struct Calendar: Decodable {
        let totalContributions: Int
    }

    static func parse(_ data: Data) throws -> ProjectGitHubActivitySnapshot {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProjectPulseError.invalidOutput
        }
        guard let viewer = response.data?.viewer else {
            throw ProjectPulseError.invalidOutput
        }
        let login = viewer.login.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard !login.isEmpty, login.count <= 100,
            login.unicodeScalars.allSatisfy(allowed.contains)
        else { throw ProjectPulseError.invalidOutput }
        let contributions = viewer.contributionsCollection
        return ProjectGitHubActivitySnapshot(
            login: login,
            totalContributions: max(contributions.contributionCalendar.totalContributions, 0),
            commitContributions: max(contributions.totalCommitContributions, 0),
            pullRequestContributions: max(contributions.totalPullRequestContributions, 0),
            reviewContributions: max(contributions.totalPullRequestReviewContributions, 0),
            issueContributions: max(contributions.totalIssueContributions, 0),
            repositoriesWithCommits: max(
                contributions.totalRepositoriesWithContributedCommits, 0),
            restrictedContributions: max(contributions.restrictedContributionsCount, 0))
    }
}

enum GitHubProjectParser {
    private struct Response: Decodable {
        let data: Payload?
    }

    private struct Payload: Decodable {
        let repository: Repository?
    }

    private struct Repository: Decodable {
        let nameWithOwner: String
        let isPrivate: Bool
        let pushedAt: String?
        let defaultBranchRef: Branch?
        let pullRequests: Count
        let issues: Count
        let stargazerCount: Int
        let forkCount: Int
    }

    private struct Branch: Decodable {
        let name: String
        let target: Target?
    }

    private struct Target: Decodable {
        let abbreviatedOid: String?
        let history: Count?
    }

    private struct Count: Decodable {
        let totalCount: Int
    }

    static func parse(_ data: Data) throws -> ProjectGitHubSnapshot {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProjectPulseError.invalidOutput
        }
        guard let repository = response.data?.repository,
            let name = ProjectPulseConfiguration.normalizedGitHubRepository(
                repository.nameWithOwner)
        else { throw ProjectPulseError.invalidOutput }
        return ProjectGitHubSnapshot(
            nameWithOwner: name,
            defaultBranch: String((repository.defaultBranchRef?.name ?? "—").prefix(120)),
            headOID: repository.defaultBranchRef?.target?.abbreviatedOid.map {
                String($0.prefix(12))
            },
            commitsLastSevenDays: max(
                repository.defaultBranchRef?.target?.history?.totalCount ?? 0, 0),
            openPullRequests: max(repository.pullRequests.totalCount, 0),
            openIssues: max(repository.issues.totalCount, 0),
            stargazerCount: max(repository.stargazerCount, 0),
            forkCount: max(repository.forkCount, 0),
            isPrivate: repository.isPrivate,
            pushedAt: repository.pushedAt.flatMap(parseDate))
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

enum GitHubRepositoryListParser {
    private struct Repository: Decodable {
        let fullName: String
        let isPrivate: Bool
        let isArchived: Bool
        let pushedAt: String?

        private enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case isPrivate = "private"
            case isArchived = "archived"
            case pushedAt = "pushed_at"
        }
    }

    static func parse(_ data: Data) throws -> [GitHubRepositoryOption] {
        let repositories: [Repository]
        do {
            repositories = try JSONDecoder().decode([Repository].self, from: data)
        } catch {
            throw ProjectPulseError.invalidOutput
        }
        var seen: Set<String> = []
        let dateFormatter = ISO8601DateFormatter()
        return repositories.compactMap { repository in
            guard let name = ProjectPulseConfiguration.normalizedGitHubRepository(
                repository.fullName),
                seen.insert(name).inserted
            else { return nil }
            return GitHubRepositoryOption(
                nameWithOwner: name,
                isPrivate: repository.isPrivate,
                isArchived: repository.isArchived,
                pushedAt: repository.pushedAt.flatMap {
                    dateFormatter.date(from: $0)
                })
        }
    }
}

enum GitHubRepositoryCatalogStatus: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

final class GitHubRepositoryCatalog: ObservableObject {
    @Published private(set) var repositories: [GitHubRepositoryOption] = []
    @Published private(set) var status: GitHubRepositoryCatalogStatus = .idle

    private let listing: GitHubRepositoryListing
    private let queue = DispatchQueue(label: "DockDeck.GitHubRepositoryCatalog", qos: .utility)
    private var requestID: UUID?

    init(listing: GitHubRepositoryListing = GitHubProjectClient()) {
        self.listing = listing
    }

    func loadIfNeeded() {
        guard status == .idle else { return }
        load()
    }

    func load() {
        guard requestID == nil else { return }
        let requestID = UUID()
        self.requestID = requestID
        status = .loading
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.listing.listRepositories() }
            DispatchQueue.main.async {
                guard self.requestID == requestID else { return }
                self.requestID = nil
                switch result {
                case .success(let repositories):
                    self.repositories = repositories
                    self.status = .ready
                case .failure(let error):
                    self.status = .failed(
                        (error as? LocalizedError)?.errorDescription
                            ?? "GitHub repositories are unavailable")
                }
            }
        }
    }
}
