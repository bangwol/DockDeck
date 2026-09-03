import SwiftUI

struct DockerSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Running, stopped, and unhealthy containers", systemImage: "shippingbox")
                        Label("Combined live CPU and memory", systemImage: "gauge.with.dots.needle.67percent")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("Metrics", systemImage: "shippingbox.fill")
                        .font(.headline)
                }

                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "Docker refresh interval",
                            selection: Binding(
                                get: { model.values.docker.refreshInterval },
                                set: model.setDockerRefreshInterval)
                        ) {
                            ForEach(DockerConfiguration.refreshIntervals, id: \.self) {
                                Text("\(Int($0)) seconds").tag($0)
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
                    "Docker uses the local Docker CLI and socket. It performs read-only ps and "
                        + "stats commands, and stops polling while the module is disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
