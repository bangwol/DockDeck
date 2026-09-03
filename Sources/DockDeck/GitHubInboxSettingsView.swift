import SwiftUI

struct GitHubInboxSettingsView: View {
    @ObservedObject var model: SettingsPanelModel
    @StateObject private var repositories: GitHubRepositoryCatalog

    init(
        model: SettingsPanelModel,
        repositories: GitHubRepositoryCatalog = GitHubRepositoryCatalog()
    ) {
        self.model = model
        _repositories = StateObject(wrappedValue: repositories)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Unread notifications", systemImage: "bell")
                        Label("Mentions and review requests", systemImage: "at")
                        Label("CI activity notifications", systemImage: "checkmark.circle")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("Account Inbox", systemImage: "tray.full")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsPickerRow(title: "Repository") {
                            Picker(
                                "Actions repository",
                                selection: Binding(
                                    get: { configuration.actionsRepository ?? "" },
                                    set: {
                                        model.setGitHubInboxActionsRepository(
                                            $0.isEmpty ? nil : $0)
                                    })
                            ) {
                                if let selected = missingSelectedRepository {
                                    Text(selected).tag(selected)
                                }
                                Text("None — show CI notifications").tag("")
                                ForEach(repositories.repositories) { repository in
                                    Label(
                                        repository.nameWithOwner,
                                        systemImage: repository.isPrivate ? "lock.fill" : "globe")
                                        .tag(repository.nameWithOwner)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 310)
                        }

                        HStack {
                            repositoryStatus
                            Spacer()
                            Button("Reload") { repositories.load() }
                                .disabled(repositories.status == .loading)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Failed Actions · Last 7 Days", systemImage: "xmark.octagon")
                        .font(.headline)
                }

                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "GitHub Inbox refresh interval",
                            selection: Binding(
                                get: { configuration.refreshInterval },
                                set: model.setGitHubInboxRefreshInterval)
                        ) {
                            ForEach(GitHubInboxConfiguration.refreshIntervals, id: \.self) {
                                Text("\(Int($0 / 60)) minutes").tag($0)
                            }
                        }
                        .labelsHidden()
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Polling", systemImage: "timer")
                        .font(.headline)
                }

                Text(
                    "GitHub CLI supplies authentication. DockDeck stores only the optional "
                        + "owner/repository name and never reads or stores your token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onAppear(perform: repositories.loadIfNeeded)
    }

    private var configuration: GitHubInboxConfiguration {
        model.values.githubInbox
    }

    @ViewBuilder private var repositoryStatus: some View {
        switch repositories.status {
        case .idle, .loading:
            Label("Loading repositories…", systemImage: "arrow.clockwise")
        case .ready:
            Text("Optional. Without a repository, the fourth metric is CI notifications.")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private var missingSelectedRepository: String? {
        guard let selected = configuration.actionsRepository,
            !repositories.repositories.contains(where: { $0.nameWithOwner == selected })
        else { return nil }
        return selected
    }
}
