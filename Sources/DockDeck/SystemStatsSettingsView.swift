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
                    Label(L10n.text("Sampling"), systemImage: "timer")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.text("Choose 2–4 tiles"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(model.values.systemStats.metrics.count) selected")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Text(L10n.text("Tile order (left to right)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(model.values.systemStats.metrics + SystemStatsMetric.allCases.filter {
                            !model.isSystemStatsMetricEnabled($0)
                        }) { metric in
                            metricRow(metric)
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
                    Label(L10n.text("Metrics"), systemImage: "gauge.with.dots.needle.67percent")
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
                    Label(L10n.text("Compact Layout"), systemImage: "rectangle.split.3x1")
                        .font(.headline)
                }

                Picker(L10n.text("Network interface"), selection: Binding(
                    get: { model.values.systemStats.networkInterfaceName }, set: model.setNetworkInterfaceName)) {
                    Text(L10n.text("Automatic (primary)")).tag("")
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

    private func metricRow(_ metric: SystemStatsMetric) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { model.isSystemStatsMetricEnabled(metric) },
                set: { model.setSystemStatsMetric(metric, enabled: $0) })
            ) {
                Label(L10n.text(metric.title), systemImage: metric.symbolName)
            }
            .toggleStyle(.checkbox)
            .disabled(!model.canSetSystemStatsMetric(
                metric, enabled: !model.isSystemStatsMetricEnabled(metric)))
            Spacer()
            if let index = model.values.systemStats.metrics.firstIndex(of: metric) {
                let moveUp = String(format: L10n.text("Move %@ up"), L10n.text(metric.title))
                let moveDown = String(format: L10n.text("Move %@ down"), L10n.text(metric.title))
                Button { model.moveSystemStatsMetric(metric, earlier: true) } label: {
                    Label(moveUp, systemImage: "chevron.up").labelStyle(.iconOnly)
                }
                .help(moveUp)
                .disabled(index == 0)
                Button { model.moveSystemStatsMetric(metric, earlier: false) } label: {
                    Label(moveDown, systemImage: "chevron.down").labelStyle(.iconOnly)
                }
                .help(moveDown)
                .disabled(index == model.values.systemStats.metrics.count - 1)
            }
        }
        .controlSize(.small)
    }

    private var availableInterfaces: [String] {
        var names = NetworkCounterReader.availableInterfaces()
        let selected = model.values.systemStats.networkInterfaceName
        if !selected.isEmpty, !names.contains(selected) { names.append(selected) }
        return names
    }

}
