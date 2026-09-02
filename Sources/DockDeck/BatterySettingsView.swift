import SwiftUI

struct BatterySettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "Battery refresh interval",
                            selection: Binding(
                                get: { model.values.battery.refreshInterval },
                                set: model.setBatteryRefreshInterval)
                        ) {
                            ForEach(PanelSettings.batteryRefreshIntervals, id: \.self) {
                                Text(String(Int($0)) + " seconds").tag($0)
                            }
                        }
                        .labelsHidden()
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Sampling", systemImage: "timer")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Charge level", systemImage: "battery.75percent")
                        Label("Power and charging state", systemImage: "bolt")
                        Label("System-provided time estimate", systemImage: "clock")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("Metrics", systemImage: "battery.100percent")
                        .font(.headline)
                }

                Text(
                    "Battery reads the internal power source through macOS IOKit. "
                        + "It requires no permission or network access and stops sampling while disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
