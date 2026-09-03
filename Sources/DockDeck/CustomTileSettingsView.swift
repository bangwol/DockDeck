import SwiftUI

struct CustomTileSettingsView: View {
    @ObservedObject var model: SettingsPanelModel
    @State private var argumentsText: String

    init(model: SettingsPanelModel) {
        self.model = model
        _argumentsText = State(
            initialValue: model.values.customTile.arguments.joined(separator: "\n"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 12) {
                        SettingsPickerRow(title: "Title") {
                            TextField(
                                "Custom Tile",
                                text: Binding(
                                    get: { configuration.title },
                                    set: model.setCustomTileTitle))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 310)
                        }
                        Divider()
                        Picker(
                            "Tile source",
                            selection: Binding(
                                get: { configuration.source },
                                set: model.setCustomTileSource)
                        ) {
                            ForEach(CustomTileSource.allCases) { source in
                                Text(source.title).tag(source)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Source", systemImage: "command")
                        .font(.headline)
                }

                if configuration.source == .executable {
                    executableSettings
                } else {
                    shortcutSettings
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Plain text: first line is the value; second line is optional detail.")
                        Text(#"{"value":"42%","detail":"Ready","symbol":"gauge"}"#)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("JSON value is required. Title, detail, and SF Symbol name are optional.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                } label: {
                    Label("Output", systemImage: "text.alignleft")
                        .font(.headline)
                }

                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "Custom Tile refresh interval",
                            selection: Binding(
                                get: { configuration.refreshInterval },
                                set: model.setCustomTileRefreshInterval)
                        ) {
                            ForEach(CustomTileConfiguration.refreshIntervals, id: \.self) {
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
                    "Commands run only while this module is enabled. DockDeck uses no shell, "
                        + "requires an absolute executable path, allows at most 16 arguments, "
                        + "and limits each run to 5 seconds and 32 KB of output. Configure only "
                        + "software you trust; it runs with your macOS user permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private var executableSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                SettingsPickerRow(title: "Executable") {
                    TextField(
                        "/usr/bin/printf",
                        text: Binding(
                            get: { configuration.executablePath },
                            set: model.setCustomTileExecutablePath))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 310)
                }
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("Arguments · one per line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(
                        text: Binding(
                            get: { argumentsText },
                            set: {
                                argumentsText = $0
                                model.setCustomTileArguments($0)
                            }))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.25)))
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Command", systemImage: "terminal")
                .font(.headline)
        }
    }

    private var shortcutSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                SettingsPickerRow(title: "Name") {
                    TextField(
                        "Shortcut name",
                        text: Binding(
                            get: { configuration.shortcutName },
                            set: model.setCustomTileShortcutName))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 310)
                }
                Text("The Shortcut must return plain text or the JSON format below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } label: {
            Label("macOS Shortcut", systemImage: "square.2.layers.3d")
                .font(.headline)
        }
    }

    private var configuration: CustomTileConfiguration { model.values.customTile }
}
