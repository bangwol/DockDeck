import Cocoa
import SwiftUI

struct DecksSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    DeckPreviewCard(side: .left, model: model)
                    DeckPreviewCard(side: .right, model: model)
                }

                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array(model.moduleDefinitions.enumerated()), id: \.element.id) {
                            index, definition in
                            if index > 0 { Divider() }
                            ModuleSettingsRow(definition: definition, model: model)
                        }
                    }
                } label: {
                    Label("Modules", systemImage: "square.grid.2x2")
                        .font(.headline)
                }

                HStack {
                    Button(action: model.swapDecks) {
                        Label("Swap Left and Right Decks", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text("At least one module stays visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }
}

struct TerminalSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 14) {
                        SettingsSliderRow(
                            title: "Width",
                            valueText: String(
                                format: "%.2f×", model.values.terminal.focusWidthMultiplier),
                            value: Binding(
                                get: {
                                    Double(model.values.terminal.focusWidthMultiplier)
                                },
                                set: { model.setFocusWidthMultiplier(CGFloat($0)) }),
                            range: Double(DockPanelLayout.minimumFocusedWidthMultiplier)
                                ... Double(DockPanelLayout.maximumFocusedWidthMultiplier),
                            step: 0.25)
                        SettingsSliderRow(
                            title: "Height",
                            valueText: String(
                                format: "%.2f×", model.values.terminal.focusHeightMultiplier),
                            value: Binding(
                                get: {
                                    Double(model.values.terminal.focusHeightMultiplier)
                                },
                                set: { model.setFocusHeightMultiplier(CGFloat($0)) }),
                            range: Double(DockPanelLayout.minimumFocusedHeightMultiplier)
                                ... Double(DockPanelLayout.maximumFocusedHeightMultiplier),
                            step: 0.25)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Focused Size", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                }

                GroupBox {
                    SettingsPickerRow(title: "Font") {
                        Picker(
                            "Terminal font",
                            selection: Binding(
                                get: { model.values.terminal.fontName },
                                set: model.setTerminalFontName)
                        ) {
                            ForEach(model.fontNames, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 230)
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
                        .frame(width: 230)
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
                            .frame(width: 230)
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
                            .frame(width: 230)
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
                        .frame(width: 230)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Sampling", systemImage: "timer")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("CPU", systemImage: "cpu")
                        Label("Memory", systemImage: "memorychip")
                        Label("Disk", systemImage: "internaldrive")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("Metrics", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.headline)
                }

                Text(
                    "All values are sampled locally with macOS system APIs. "
                        + "Sampling stops completely while this module is disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

struct ServiceMonitorSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 10) {
                        if model.values.serviceMonitor.endpoints.isEmpty {
                            Text("Add up to four HTTPS health or service URLs.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(model.values.serviceMonitor.endpoints) { endpoint in
                                ServiceMonitorEndpointRow(endpoint: endpoint, model: model)
                                if endpoint.id != model.values.serviceMonitor.endpoints.last?.id {
                                    Divider()
                                }
                            }
                        }

                        HStack {
                            Button(action: model.addServiceMonitorEndpoint) {
                                Label("Add Service", systemImage: "plus")
                            }
                            .disabled(
                                model.values.serviceMonitor.endpoints.count
                                    >= ServiceMonitorEndpoint.maximumCount)
                            Spacer()
                            Text(
                                "\(model.values.serviceMonitor.endpoints.count)"
                                    + "/\(ServiceMonitorEndpoint.maximumCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Services", systemImage: "network")
                        .font(.headline)
                }

                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "Service Monitor refresh interval",
                            selection: Binding(
                                get: { model.values.serviceMonitor.refreshInterval },
                                set: model.setServiceMonitorRefreshInterval)
                        ) {
                            ForEach(PanelSettings.serviceMonitorRefreshIntervals, id: \.self) {
                                Text("\(Int($0)) seconds").tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 230)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Polling", systemImage: "timer")
                        .font(.headline)
                }

                Text(
                    "Checks use an ephemeral, cookie-free HEAD request. Public services require "
                        + "HTTPS; HTTP is limited to local addresses. URLs containing credentials "
                        + "or common secret query fields are rejected and never saved. Avoid "
                        + "secret-bearing URL paths. Local addresses may request macOS Local "
                        + "Network permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 14) {
                        SettingsSliderRow(
                            title: "Corner Radius",
                            valueText: String(
                                format: "%.0f pt", model.values.appearance.cornerRadius),
                            value: Binding(
                                get: { Double(model.values.appearance.cornerRadius) },
                                set: { model.setCornerRadius(CGFloat($0)) }),
                            range: 0...24,
                            step: 1)
                        SettingsSliderRow(
                            title: "Theme Tint",
                            valueText: String(
                                format: "%.0f%%", model.values.appearance.tintOpacity * 100),
                            value: Binding(
                                get: { Double(model.values.appearance.tintOpacity) },
                                set: { model.setTintOpacity(CGFloat($0)) }),
                            range: 0.2...1,
                            step: 0.01)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Panel Surface", systemImage: "circle.lefthalf.filled")
                        .font(.headline)
                }

                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reset Settings")
                            Text("Restore all module and appearance defaults.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset to Defaults") { model.onReset?() }
                    }
                    .padding(.vertical, 6)
                } label: {
                    Label("Defaults", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                }
            }
            .padding(24)
        }
    }
}

private struct DeckPreviewCard: View {
    let side: PanelSide
    @ObservedObject var model: SettingsPanelModel

    private var title: String { side == .left ? "Left Deck" : "Right Deck" }

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                ForEach(model.moduleDefinitions(on: side)) { definition in
                    HStack(spacing: 10) {
                        Image(systemName: definition.symbolName)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(definition.title)
                                .fontWeight(.medium)
                            Text(definition.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(
                            systemName: model.isEnabled(definition.id)
                                ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(
                                model.isEnabled(definition.id) ? Color.accentColor : .secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08)))
                    .opacity(model.isEnabled(definition.id) ? 1 : 0.55)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .top)
        } label: {
            Label(title, systemImage: "rectangle.stack")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ModuleSettingsRow: View {
    let definition: PanelModuleDefinition
    @ObservedObject var model: SettingsPanelModel

    private var sideTitle: String {
        switch model.side(containing: definition.id) {
        case .left: "Left"
        case .right: "Right"
        case nil: "Unplaced"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: definition.symbolName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.title)
                Text(definition.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let pane = definition.settingsPane {
                Button {
                    model.selectPane(pane)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("Configure \(definition.title)")
            }
            Text(sideTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            Toggle(
                "Show \(definition.title)",
                isOn: Binding(
                    get: { model.isEnabled(definition.id) },
                    set: { model.setEnabled($0, for: definition.id) }))
                .labelsHidden()
                .disabled(!model.canDisable(definition.id))
                .help(
                    model.canDisable(definition.id)
                        ? "Show or hide \(definition.title)"
                        : "DockDeck keeps one module visible so Settings remains accessible")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
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

private struct ServiceMonitorEndpointRow: View {
    let endpoint: ServiceMonitorEndpoint
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField(
                    "Name",
                    text: Binding(
                        get: { currentEndpoint.name },
                        set: { model.setServiceMonitorEndpointName(endpoint.id, name: $0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                TextField(
                    "https://status.example.com/health",
                    text: Binding(
                        get: { currentEndpoint.urlString },
                        set: { model.setServiceMonitorEndpointURL(endpoint.id, urlString: $0) }))
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.removeServiceMonitorEndpoint(endpoint.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove \(currentEndpoint.displayName)")
                .accessibilityLabel("Remove \(currentEndpoint.displayName)")
            }

            if let message = ServiceMonitorURLValidator.validationMessage(
                currentEndpoint.urlString)
            {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private var currentEndpoint: ServiceMonitorEndpoint {
        model.values.serviceMonitor.endpoints.first { $0.id == endpoint.id } ?? endpoint
    }
}

private struct SettingsSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

struct SettingsPickerRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }
}
