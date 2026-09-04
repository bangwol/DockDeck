import Cocoa
import SwiftUI

struct UsageSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array(UsageProviderID.allCases.enumerated()), id: \.element) {
                            index, provider in
                            if index > 0 { Divider() }
                            UsageProviderSettingsRow(provider: provider, model: model)
                        }
                    }
                } label: {
                    Label("Providers", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsPickerRow(title: "Mode") {
                            Picker(
                                "Claude refresh",
                                selection: Binding(
                                    get: { model.values.usage.claudeRefreshMode },
                                    set: model.setClaudeUsageRefreshMode)
                            ) {
                                ForEach(ClaudeUsageRefreshMode.allCases, id: \.self) {
                                    Text($0.title).tag($0)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                        Divider()
                        Text(model.values.usage.claudeRefreshMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                } label: {
                    Label("Claude Refresh", systemImage: "arrow.clockwise")
                        .font(.headline)
                }

                GroupBox {
                    VStack(spacing: 12) {
                        SettingsPickerRow(title: "Values") {
                            Picker(
                                "Usage values",
                                selection: Binding(
                                    get: { model.values.usage.displayMode },
                                    set: model.setUsageDisplayMode)
                            ) {
                                ForEach(UsageDisplayMode.allCases, id: \.self) {
                                    Text($0.title).tag($0)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                        Divider()
                        SettingsSwitchRow(
                            title: "Even-use marker",
                            subtitle: "Compare quota use with elapsed time in each window.",
                            isOn: Binding(
                                get: { model.values.usage.showsPace },
                                set: model.setUsageShowsPace))
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Display", systemImage: "percent")
                        .font(.headline)
                }

                GroupBox {
                    VStack(spacing: 14) {
                        SettingsPickerRow(title: "Font") {
                            Picker(
                                "Usage font",
                                selection: Binding(
                                    get: { model.values.usage.fontName },
                                    set: model.setUsageFontName)
                            ) {
                                ForEach(model.fontNames, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                        }
                        SettingsSliderRow(
                            title: "Size",
                            valueText: String(
                                format: "%.0f pt", model.values.usage.fontSize),
                            value: Binding(
                                get: { Double(model.values.usage.fontSize) },
                                set: { model.setUsageFontSize(CGFloat($0)) }),
                            range: Double(PanelSettings.minimumUsageFontSize)
                                ... Double(PanelSettings.maximumUsageFontSize),
                            step: 1)
                        SettingsPickerRow(title: "Color") {
                            Picker(
                                "Usage text color",
                                selection: Binding(
                                    get: { model.values.usage.textColor },
                                    set: model.setUsageTextColor)
                            ) {
                                ForEach(UsageTextColor.allCases, id: \.self) {
                                    Text($0.title).tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Text", systemImage: "textformat")
                        .font(.headline)
                }
            }
            .padding(24)
        }
    }
}
private struct UsageProviderSettingsRow: View {
    let provider: UsageProviderID
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.title)
                Text(provider.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "Show \(provider.title)",
                isOn: Binding(
                    get: { model.isUsageProviderEnabled(provider) },
                    set: { model.setUsageProvider(provider, enabled: $0) }))
                .labelsHidden()
                .disabled(!model.canDisableUsageProvider(provider))
                .help(
                    model.canDisableUsageProvider(provider)
                        ? "Show \(provider.title) and refresh its data"
                        : "Keep at least one usage provider enabled")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}
