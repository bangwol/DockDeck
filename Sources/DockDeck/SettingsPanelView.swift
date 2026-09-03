import Cocoa
import SwiftUI

final class SettingsPanelView: NSView {
    static let preferredSize = NSSize(width: 740, height: 540)
    static let sidebarWidth: CGFloat = 200

    private let model: SettingsPanelModel
    private let hostingView: NSHostingView<SettingsRootView>

    var onPaneChange: ((SettingsPaneID) -> Void)? {
        get { model.onPaneChange }
        set { model.onPaneChange = newValue }
    }
    var onChange: ((SettingsPanelChange) -> Void)? {
        get { model.onChange }
        set { model.onChange = newValue }
    }
    var onReset: (() -> Void)? {
        get { model.onReset }
        set { model.onReset = newValue }
    }
    var onCancel: (() -> Void)? {
        get { model.onCancel }
        set { model.onCancel = newValue }
    }

    init(
        selectedPane: SettingsPaneID,
        values: SettingsPanelValues,
        fontNames: [String],
        scheduleStore: ScheduleStore = ScheduleStore(),
        diagnosticsStore: DiagnosticsStore = DiagnosticsStore()
    ) {
        let model = SettingsPanelModel(
            selectedPane: selectedPane, values: values, fontNames: fontNames)
        self.model = model
        hostingView = NSHostingView(
            rootView: SettingsRootView(
                model: model,
                scheduleStore: scheduleStore,
                diagnosticsStore: diagnosticsStore))

        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        setAccessibilityLabel("DockDeck Settings")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func selectPane(_ pane: SettingsPaneID) {
        model.selectPane(pane)
    }

    func setValues(_ values: SettingsPanelValues) {
        model.setValues(values)
    }

    @objc override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private struct SettingsRootView: View {
    @ObservedObject var model: SettingsPanelModel
    @ObservedObject var scheduleStore: ScheduleStore
    @ObservedObject var diagnosticsStore: DiagnosticsStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "dock.rectangle")
                        .foregroundStyle(.secondary)
                    Text("DockDeck")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 54)

                List(selection: $model.selectedPane) {
                    ForEach(model.sidebarSections) { section in
                        Section(section.title) {
                            ForEach(section.panes) { pane in
                                SettingsSidebarRow(pane: pane, model: model)
                                    .tag(pane)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Settings categories")
            }
            .frame(width: SettingsPanelView.sidebarWidth)
            .background(SidebarBackdrop())

            Divider()

            VStack(spacing: 0) {
                SettingsHeader(pane: model.selectedPane, model: model)
                Divider()
                if let definition = selectedModule, !model.isEnabled(definition.id) {
                    DisabledModuleNotice(moduleTitle: definition.title)
                    Divider()
                }
                selectedPane
                    .disabled(selectedModule.map { !model.isEnabled($0.id) } ?? false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            minWidth: SettingsPanelView.preferredSize.width,
            minHeight: SettingsPanelView.preferredSize.height)
    }

    private var selectedModule: PanelModuleDefinition? {
        model.moduleDefinition(for: model.selectedPane)
    }

    @ViewBuilder private var selectedPane: some View {
        switch model.selectedPane {
        case .decks:
            DecksSettingsView(model: model)
        case .notifications:
            NotificationSettingsView(model: model)
        case .diagnostics:
            DiagnosticsSettingsView(store: diagnosticsStore)
        case .terminal:
            TerminalSettingsView(model: model)
        case .usage:
            UsageSettingsView(model: model)
        case .systemStats:
            SystemStatsSettingsView(model: model)
        case .serviceMonitor:
            ServiceMonitorSettingsView(model: model)
        case .weather:
            WeatherSettingsView(model: model)
        case .schedule:
            ScheduleSettingsView(model: model, store: scheduleStore)
        case .clock:
            ClockSettingsView(model: model)
        case .battery:
            BatterySettingsView(model: model)
        case .network:
            NetworkSettingsView(model: model)
        case .projectPulse:
            ProjectPulseSettingsView(model: model)
        case .githubInbox:
            GitHubInboxSettingsView(model: model)
        case .docker:
            DockerSettingsView(model: model)
        case .focusTimer:
            FocusTimerSettingsView(model: model)
        case .appearance:
            AppearanceSettingsView(model: model)
        }
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPaneID
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        HStack(spacing: 8) {
            Label(pane.title, systemImage: pane.symbolName)
            Spacer()
            if let definition = model.moduleDefinition(for: pane) {
                Circle()
                    .fill(
                        model.isEnabled(definition.id)
                            ? Color.accentColor : Color.secondary.opacity(0.45))
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(
                        model.isEnabled(definition.id) ? "Enabled" : "Disabled")
            }
        }
    }
}

/// One sidebar material behind both the header and the list. A flat `underPageBackgroundColor`
/// left a darker band above the list in light mode because the sidebar list paints its own surface.
private struct SidebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct SettingsHeader: View {
    let pane: SettingsPaneID
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pane.symbolName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.title2.weight(.semibold))
                Text(pane.subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let definition = model.moduleDefinition(for: pane) {
                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { model.isEnabled(definition.id) },
                        set: { model.setEnabled($0, for: definition.id) }))
                    .toggleStyle(.switch)
                    .disabled(!model.canDisable(definition.id))
                    .help(
                        model.canDisable(definition.id)
                            ? "Run and show \(definition.title)"
                            : "DockDeck keeps one module visible so Settings remains accessible")
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
    }
}

private struct DisabledModuleNotice: View {
    let moduleTitle: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle")
            Text("Enable \(moduleTitle) to run it and apply these settings.")
                .font(.callout)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .frame(height: 42)
        .background(Color.primary.opacity(0.035))
    }
}
