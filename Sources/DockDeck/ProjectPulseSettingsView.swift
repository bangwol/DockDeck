import AppKit
import SwiftUI

struct ProjectPulseSettingsView: View {
    @ObservedObject var model: SettingsPanelModel
    @StateObject private var githubRepositories: GitHubRepositoryCatalog

    init(
        model: SettingsPanelModel,
        githubRepositories: GitHubRepositoryCatalog = GitHubRepositoryCatalog()
    ) {
        self.model = model
        _githubRepositories = StateObject(wrappedValue: githubRepositories)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(
                            "Repository source",
                            selection: Binding(
                                get: { configuration.source },
                                set: selectSource)
                        ) {
                            ForEach(ProjectPulseSource.allCases) { source in
                                Text(source.title).tag(source)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        Text(sourceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                } label: {
                    Label("Source", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                }

                if configuration.source == .local {
                    localRepositorySettings
                } else {
                    githubSettings
                }

                if configuration.source == .local || configuration.githubScope == .repository {
                    GroupBox {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Latest Actions run")
                                    Text("Show the latest workflow result beside the repository name.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 16)
                                Toggle(
                                    "Latest Actions run",
                                    isOn: Binding(
                                        get: { configuration.includesGitHubActions },
                                        set: model.setProjectPulseIncludesGitHubActions))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .disabled(!configuration.isConfigured)
                            }
                            Divider()
                            HStack {
                                Link(
                                    "GitHub CLI setup",
                                    destination: URL(string: "https://cli.github.com/")!)
                                Spacer()
                                Text("Optional for local · Required for GitHub")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Label("Continuous Integration", systemImage: "checkmark.circle")
                            .font(.headline)
                    }
                }

                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "Project Pulse refresh interval",
                            selection: Binding(
                                get: { configuration.refreshInterval },
                                set: model.setProjectPulseRefreshInterval)
                        ) {
                            ForEach(refreshIntervals, id: \.self) {
                                Text($0 < 60 ? "\(Int($0)) seconds" : "\(Int($0 / 60)) minutes")
                                    .tag($0)
                            }
                        }
                        .labelsHidden()
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Polling", systemImage: "timer")
                        .font(.headline)
                }

                Text(privacyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onAppear {
            if configuration.source == .github, configuration.githubScope == .repository {
                githubRepositories.loadIfNeeded()
            }
        }
    }

    private var configuration: ProjectPulseConfiguration {
        model.values.projectPulse
    }

    private var localRepositorySettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let path = configuration.repositoryPath {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .fontWeight(.medium)
                            Text((path as NSString).abbreviatingWithTildeInPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Clear") { model.setProjectPulseRepositoryPath(nil) }
                    }
                    Divider()
                } else {
                    Text("Choose one local Git repository to monitor.")
                        .foregroundStyle(.secondary)
                }

                Button(action: chooseRepository) {
                    Label("Choose Repository…", systemImage: "folder.badge.plus")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label("Local Repository", systemImage: "folder")
                .font(.headline)
        }
    }

    private var githubSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                SettingsPickerRow(title: "View") {
                    Picker(
                        "GitHub view",
                        selection: Binding(
                            get: { configuration.githubScope },
                            set: selectGitHubScope)
                    ) {
                        ForEach(GitHubPulseScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                Divider()
                if configuration.githubScope == .repository {
                    SettingsPickerRow(title: "Repository") {
                        Picker(
                            "GitHub repository",
                            selection: Binding(
                                get: { configuration.githubRepository ?? "" },
                                set: { model.setProjectPulseGitHubRepository($0) })
                        ) {
                            if let selected = selectedRepositoryMissingFromCatalog {
                                Text(selected).tag(selected)
                            }
                            Text("Choose…").tag("")
                            ForEach(githubRepositories.repositories) { repository in
                                Label(
                                    repository.nameWithOwner,
                                    systemImage: repository.isArchived
                                        ? "archivebox.fill"
                                        : (repository.isPrivate ? "lock.fill" : "globe"))
                                    .tag(repository.nameWithOwner)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 300)
                        .disabled(githubRepositories.status != .ready)
                    }

                    switch githubRepositories.status {
                    case .idle, .loading:
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Reading repositories from GitHub CLI…")
                                .foregroundStyle(.secondary)
                        }
                    case .failed(let message):
                        Label(message, systemImage: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    case .ready:
                        if githubRepositories.repositories.isEmpty {
                            Text("No accessible repositories were returned by GitHub.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()
                    HStack {
                        Text("Most recently pushed accessible repositories, up to 100.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: githubRepositories.load) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(githubRepositories.status == .loading)
                    }
                } else {
                    Label {
                        Text(
                            "Summarize your last 7 days of GitHub contributions across "
                                + "repositories. Activity uses a 5-minute base interval."
                        )
                        .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label("GitHub", systemImage: "network")
                .font(.headline)
        }
    }

    private var selectedRepositoryMissingFromCatalog: String? {
        guard let selected = configuration.githubRepository,
            !githubRepositories.repositories.contains(where: {
                $0.nameWithOwner == selected
            })
        else { return nil }
        return selected
    }

    private var sourceDescription: String {
        switch configuration.source {
        case .local:
            "Read branch and working-tree state directly from a folder on this Mac."
        case .github:
            "Use your signed-in GitHub CLI for one repository or your recent activity."
        }
    }

    private var privacyDescription: String {
        switch configuration.source {
        case .local:
            "Git status is read locally and file names are discarded. Optional Actions data "
                + "uses GitHub CLI non-interactively."
        case .github:
            if configuration.githubScope == .activity {
                "DockDeck keeps aggregated 7-day contribution counts in memory. GitHub CLI "
                    + "supplies authentication; DockDeck never reads or stores its token."
            } else {
                "DockDeck stores the selected owner/repository name. GitHub CLI supplies "
                    + "authentication for repository metadata and optional Actions data; "
                    + "DockDeck never reads or stores its token."
            }
        }
    }

    private var refreshIntervals: [TimeInterval] {
        if configuration.source == .github, configuration.githubScope == .activity {
            return ProjectPulseConfiguration.refreshIntervals.filter { $0 >= 5 * 60 }
        }
        return ProjectPulseConfiguration.refreshIntervals
    }

    private func selectSource(_ source: ProjectPulseSource) {
        model.setProjectPulseSource(source)
        if source == .github, configuration.githubScope == .repository {
            githubRepositories.loadIfNeeded()
        }
    }

    private func selectGitHubScope(_ scope: GitHubPulseScope) {
        model.setProjectPulseGitHubScope(scope)
        if scope == .repository { githubRepositories.loadIfNeeded() }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Git Repository"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let path = configuration.repositoryPath {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setProjectPulseRepositoryPath(url.path)
    }
}
