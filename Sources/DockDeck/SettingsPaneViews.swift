import Cocoa
import SwiftUI
import UniformTypeIdentifiers

enum DeckModuleDragPayload {
    static let contentType = UTType.utf8PlainText

    private static let prefix = "dockdeck-module:"

    static func itemProvider(for module: PanelModuleID) -> NSItemProvider {
        NSItemProvider(object: "\(prefix)\(module.rawValue)" as NSString)
    }

    static func moduleID(from text: String) -> PanelModuleID? {
        guard text.hasPrefix(prefix) else { return nil }
        let module = PanelModuleID(rawValue: String(text.dropFirst(prefix.count)))
        return PanelModuleRegistry.definition(for: module) == nil ? nil : module
    }
}

struct DecksSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    DeckPreviewCard(side: .left, model: model)
                    DeckPreviewCard(side: .right, model: model)
                }

                HStack {
                    Button(action: model.swapDecks) {
                        Label("Swap Left and Right Decks", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text("Drag the ≡ handle to arrange. Enabled modules stay above hidden modules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }
}

struct NotificationSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Allow local notifications")
                            Text("macOS asks for permission only when you turn this on.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(
                            "Allow local notifications",
                            isOn: Binding(
                                get: { model.values.notifications.enabled },
                                set: model.setNotificationsEnabled))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Notifications", systemImage: "bell.badge")
                        .font(.headline)
                }

                GroupBox {
                    VStack(spacing: 12) {
                        SettingsSwitchRow(
                            title: "Usage limits",
                            subtitle: "Alert when a live quota window reaches the threshold.",
                            isOn: Binding(
                                get: { model.values.notifications.usageAlerts },
                                set: model.setUsageAlertsEnabled))
                        Divider()
                        SettingsPickerRow(title: "Remaining") {
                            Picker(
                                "Usage remaining threshold",
                                selection: Binding(
                                    get: {
                                        model.values.notifications.usageRemainingThreshold
                                    },
                                    set: model.setUsageAlertThreshold)
                            ) {
                                ForEach(DockNotificationSettings.usageThresholds, id: \.self) {
                                    Text("\($0)%").tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Usage", systemImage: "chart.bar")
                        .font(.headline)
                }
                .disabled(!model.values.notifications.enabled)

                GroupBox {
                    VStack(spacing: 12) {
                        SettingsSwitchRow(
                            title: "Service failures",
                            subtitle: "Alert once when a configured endpoint goes down.",
                            isOn: Binding(
                                get: {
                                    model.values.notifications.serviceFailureAlerts
                                },
                                set: model.setServiceFailureAlertsEnabled))
                        Divider()
                        SettingsSwitchRow(
                            title: "Service recoveries",
                            subtitle: "Alert when a failed endpoint responds again.",
                            isOn: Binding(
                                get: {
                                    model.values.notifications.serviceRecoveryAlerts
                                },
                                set: model.setServiceRecoveryAlertsEnabled))
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Service Monitor", systemImage: "server.rack")
                        .font(.headline)
                }
                .disabled(!model.values.notifications.enabled)

                GroupBox {
                    VStack(spacing: 12) {
                        SettingsSwitchRow(
                            title: "Low battery",
                            subtitle: "Alert on battery power when charge reaches the threshold.",
                            isOn: Binding(
                                get: { model.values.notifications.batteryAlerts },
                                set: model.setBatteryAlertsEnabled))
                        Divider()
                        SettingsPickerRow(title: "Remaining") {
                            Picker(
                                "Battery remaining threshold",
                                selection: Binding(
                                    get: {
                                        model.values.notifications.batteryRemainingThreshold
                                    },
                                    set: model.setBatteryAlertThreshold)
                            ) {
                                ForEach(DockNotificationSettings.batteryThresholds, id: \.self) {
                                    Text("\($0)%").tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Battery", systemImage: "battery.25percent")
                        .font(.headline)
                }
                .disabled(!model.values.notifications.enabled)

                Text(
                    "Alerts are generated locally from DockDeck's existing module data and only "
                        + "when a condition changes. If macOS access is blocked, allow DockDeck in "
                        + "System Settings → Notifications. Notification previews can include a "
                        + "provider or service name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

private struct SettingsSwitchRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
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
                            "GPU load still needs a private or privileged source and is not sampled.",
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
                        Label("Percent bars for CPU, memory, and disk", systemImage: "chart.bar.fill")
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
                    Label("Services", systemImage: "server.rack")
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
    @State private var isConfirmingReset = false

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
                        Button("Reset to Defaults") { isConfirmingReset = true }
                            .confirmationDialog(
                                "Reset all DockDeck settings?",
                                isPresented: $isConfirmingReset,
                                titleVisibility: .visible
                            ) {
                                Button("Reset to Defaults", role: .destructive) {
                                    model.onReset?()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(
                                    "Deck layout, Service Monitor URLs, the Weather city, and "
                                        + "appearance return to their defaults. Themes are kept.")
                            }
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
                let definitions = model.moduleDefinitions(on: side)
                if definitions.isEmpty {
                    EmptyDeckDropZone()
                } else {
                    ForEach(definitions) { definition in
                        DeckModuleCard(
                            definition: definition,
                            side: side,
                            model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .top)
        } label: {
            Label(title, systemImage: "rectangle.stack")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .onDrop(
            of: [DeckModuleDragPayload.contentType],
            delegate: DeckModuleDropDelegate(side: side, target: nil, model: model))
    }
}

private struct EmptyDeckDropZone: View {
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "square.and.arrow.down")
                .font(.title3)
            Text("Drop modules here")
                .font(.callout.weight(.medium))
            Text("This side stays hidden while empty.")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.025)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty deck. Drop modules here. This side stays hidden.")
    }
}

private struct DeckModuleCard: View {
    let definition: PanelModuleDefinition
    let side: PanelSide
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 28)
                .contentShape(Rectangle())
                .onDrag {
                    DeckModuleDragPayload.itemProvider(for: definition.id)
                }
                .accessibilityLabel("Drag \(definition.title)")
            Image(systemName: definition.symbolName)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(definition.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(definition.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "Show \(definition.title)",
                isOn: Binding(
                    get: { model.isEnabled(definition.id) },
                    set: { model.setEnabled($0, for: definition.id) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!model.canDisable(definition.id))
                .help(
                    model.canDisable(definition.id)
                        ? "Run and show \(definition.title)"
                        : "DockDeck keeps one module enabled so Settings remains accessible")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08)))
        .opacity(model.isEnabled(definition.id) ? 1 : 0.55)
        .contentShape(Rectangle())
        .onDrop(
            of: [DeckModuleDragPayload.contentType],
            delegate: DeckModuleDropDelegate(
                side: side, target: definition.id, model: model))
        .contextMenu {
            if let pane = definition.settingsPane {
                Button("Configure \(definition.title)…") { model.selectPane(pane) }
                Divider()
            }
            let destination = side.opposite
            Button("Move to \(destination == .left ? "Left" : "Right") Deck") {
                model.moveModule(definition.id, to: destination)
            }
            Divider()
            Button("Move Up") { model.moveModuleUp(definition.id) }
                .disabled(!model.canMoveModuleUp(definition.id))
            Button("Move Down") { model.moveModuleDown(definition.id) }
                .disabled(!model.canMoveModuleDown(definition.id))
        }
        .accessibilityAction(
            named: Text("Move to \(side.opposite == .left ? "Left" : "Right") Deck")
        ) {
            model.moveModule(definition.id, to: side.opposite)
        }
        .help("Drag the ≡ handle to move or reorder \(definition.title)")
    }
}

private struct DeckModuleDropDelegate: DropDelegate {
    let side: PanelSide
    let target: PanelModuleID?
    let model: SettingsPanelModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [DeckModuleDragPayload.contentType])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard
            let provider = info.itemProviders(
                for: [DeckModuleDragPayload.contentType]
            ).first
        else { return false }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString,
                let module = DeckModuleDragPayload.moduleID(from: text as String)
            else { return }
            DispatchQueue.main.async {
                model.moveModule(module, to: side, before: target)
            }
        }
        return true
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

/// Label on the leading edge, control on the trailing edge, matching System Settings. Controls
/// keep their intrinsic width so every row's control shares the same right edge as the sliders.
struct SettingsPickerRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            content()
                .frame(maxWidth: 260, alignment: .trailing)
        }
    }
}
