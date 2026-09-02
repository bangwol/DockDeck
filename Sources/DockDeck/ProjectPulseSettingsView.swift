import AppKit
import SwiftUI

struct ProjectPulseSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        if let path = model.values.projectPulse.repositoryPath {
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
                                Button("Clear") {
                                    model.setProjectPulseRepositoryPath(nil)
                                }
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
                    Label("Repository", systemImage: "folder")
                        .font(.headline)
                }

                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("GitHub Actions")
                                Text("Use the signed-in GitHub CLI to read the latest run.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 16)
                            Toggle(
                                "GitHub Actions",
                                isOn: Binding(
                                    get: {
                                        model.values.projectPulse.includesGitHubActions
                                    },
                                    set: model.setProjectPulseIncludesGitHubActions))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        Divider()
                        HStack {
                            Link("GitHub CLI setup", destination: URL(string: "https://cli.github.com/")!)
                            Spacer()
                            Text("Optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Continuous Integration", systemImage: "checkmark.circle")
                        .font(.headline)
                }
                .disabled(model.values.projectPulse.repositoryPath == nil)

                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "Project Pulse refresh interval",
                            selection: Binding(
                                get: { model.values.projectPulse.refreshInterval },
                                set: model.setProjectPulseRefreshInterval)
                        ) {
                            ForEach(ProjectPulseConfiguration.refreshIntervals, id: \.self) {
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

                Text(
                    "Git status is read locally and file names are discarded. When Actions is "
                        + "enabled, DockDeck runs `gh run list` non-interactively in the selected "
                        + "repository. It does not read, copy, or store GitHub tokens or remote URLs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Git Repository"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let path = model.values.projectPulse.repositoryPath {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setProjectPulseRepositoryPath(url.path)
    }
}
