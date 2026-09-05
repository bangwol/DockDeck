import Cocoa
import SwiftUI

struct SystemStatsSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "System Stats refresh interval",
                            selection: Binding(
                                get: { model.values.systemStats.refreshInterval },
                                set: model.setSystemStatsRefreshInterval)
                        ) {
                            ForEach(PanelSettings.systemStatsRefreshIntervals, id: \.self) {
                                Text("\(Int($0)) seconds").tag($0)
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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Choose 2–4 tiles")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(model.values.systemStats.metrics.count) selected")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading),
                            ],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(SystemStatsMetric.allCases) { metric in
                                let enabled = model.isSystemStatsMetricEnabled(metric)
                                Toggle(
                                    isOn: Binding(
                                        get: { model.isSystemStatsMetricEnabled(metric) },
                                        set: { model.setSystemStatsMetric(metric, enabled: $0) })
                                ) {
                                    Label(metric.title, systemImage: metric.symbolName)
                                }
                                .toggleStyle(.checkbox)
                                .disabled(
                                    !model.canSetSystemStatsMetric(metric, enabled: !enabled))
                            }
                        }

                        Divider()

                        Label(
                            InstalledTemperatureReader.isAvailable
                                ? "Temperature source: signed Stats SMC tool (read-only)."
                                : "Temperature source unavailable; the tile shows --°.",
                            systemImage: InstalledTemperatureReader.isAvailable
                                ? "checkmark.shield" : "thermometer.medium")
                        Label(
                            "The temperature bar uses the public macOS thermal-pressure state.",
                            systemImage: "gauge.with.dots.needle.33percent")
                        Label(
                            "GPU uses local driver counters when available; unsupported drivers show --.",
                            systemImage: "lock.shield")
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("Metrics", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Percent bars for CPU, GPU, memory, and disk", systemImage: "chart.bar.fill")
                        Label("Compact download and upload rates for Network I/O", systemImage: "arrow.up.arrow.down")
                        Label(
                            "Numeric hottest-CPU-core value with a pressure bar",
                            systemImage: "thermometer.medium")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("Compact Layout", systemImage: "rectangle.split.3x1")
                        .font(.headline)
                }

                Picker("Network interface", selection: Binding(
                    get: { model.values.systemStats.networkInterfaceName }, set: model.setNetworkInterfaceName)) {
                    Text("Automatic (primary)").tag("")
                    ForEach(availableInterfaces, id: \.self) { Text($0).tag($0) }
                }
                Text("Select Network I/O to sample download/upload counters. A VPN interface may disappear after disconnecting. System route status always describes the macOS connection.")
                    .font(.caption).foregroundStyle(.secondary)

                Text(
                    "Only selected values are sampled with local macOS APIs. The four-tile limit "
                        + "keeps labels readable at the 214 × 59 point compact panel size. "
                        + "Temperature is checked at most every 15 seconds. Sampling stops "
                        + "completely while this module is disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
    private var availableInterfaces: [String] {
        var names = NetworkCounterReader.availableInterfaces()
        let selected = model.values.systemStats.networkInterfaceName
        if !selected.isEmpty, !names.contains(selected) { names.append(selected) }
        return names
    }

}
