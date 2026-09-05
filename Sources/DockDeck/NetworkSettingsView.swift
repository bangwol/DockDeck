import SwiftUI

struct NetworkSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Interface", selection: Binding(
                    get: { model.values.network.interfaceName }, set: model.setNetworkInterfaceName)) {
                    Text("Automatic (primary)").tag("")
                    ForEach(availableInterfaces, id: \.self) { name in Text(name).tag(name) }
                }
                Text("A selected interface may disappear when a VPN disconnects. Internet route status refers to the system connection.")
                    .font(.caption).foregroundStyle(.secondary)
                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "Network refresh interval",
                            selection: Binding(
                                get: { model.values.network.refreshInterval },
                                set: model.setNetworkRefreshInterval)
                        ) {
                            ForEach(PanelSettings.networkRefreshIntervals, id: \.self) {
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
                        Label("Download rate", systemImage: "arrow.down")
                        Label("Upload rate", systemImage: "arrow.up")
                        Label("Current primary interface", systemImage: "network")
                        Label("Connection and Low Data status", systemImage: "wifi")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("Metrics", systemImage: "network")
                        .font(.headline)
                }

                Text(
                    "Network reads macOS byte counters and Network framework status. "
                        + "It does not inspect traffic, addresses, hostnames, or packet contents. "
                        + "Sampling stops while disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
    private var availableInterfaces: [String] {
        var names = NetworkCounterReader.availableInterfaces()
        let selected = model.values.network.interfaceName
        if !selected.isEmpty, !names.contains(selected) { names.append(selected) }
        return names
    }

}
