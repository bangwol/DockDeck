import Cocoa
import SwiftUI

enum SettingsPaneID: String, CaseIterable, Identifiable {
    case decks
    case terminal
    case usage
    case appearance

    var id: Self { self }

    var title: String {
        switch self {
        case .decks: "Decks"
        case .terminal: "Terminal"
        case .usage: "Usage"
        case .appearance: "Appearance"
        }
    }

    var subtitle: String {
        switch self {
        case .decks: "Choose which modules appear beside the Dock."
        case .terminal: "Control terminal expansion and text."
        case .usage: "Choose how account limits are displayed."
        case .appearance: "Adjust the shared panel surface."
        }
    }

    var symbolName: String {
        switch self {
        case .decks: "rectangle.stack"
        case .terminal: "terminal"
        case .usage: "chart.bar"
        case .appearance: "paintbrush"
        }
    }

    var windowTitle: String { "DockDeck — \(title)" }
}

struct PanelModuleDefinition: Identifiable, Equatable {
    let id: PanelModuleID
    let title: String
    let subtitle: String
    let symbolName: String

    static func definition(for id: PanelModuleID) -> Self? {
        switch id {
        case .terminal:
            Self(
                id: id, title: "Terminal", subtitle: "Interactive login shell",
                symbolName: "terminal")
        case .usage:
            Self(
                id: id, title: "Usage", subtitle: "Codex and Claude limits",
                symbolName: "chart.bar")
        default:
            nil
        }
    }
}

final class SettingsPanelModel: ObservableObject {
    @Published var selectedPane: SettingsPaneID {
        didSet { onPaneChange?(selectedPane) }
    }
    @Published private(set) var deckConfiguration: PanelDeckConfiguration
    @Published private(set) var cornerRadius: CGFloat
    @Published private(set) var tintOpacity: CGFloat
    @Published private(set) var focusWidthMultiplier: CGFloat
    @Published private(set) var focusHeightMultiplier: CGFloat
    @Published private(set) var terminalFontName: String
    @Published private(set) var usageFontName: String
    @Published private(set) var usageFontSize: CGFloat
    @Published private(set) var usageDisplayMode: UsageDisplayMode
    @Published private(set) var usageTextColor: UsageTextColor

    let fontNames: [String]

    var onPaneChange: ((SettingsPaneID) -> Void)?
    var onDeckConfigurationChange: ((PanelDeckConfiguration) -> Void)?
    var onCornerRadiusChange: ((CGFloat) -> Void)?
    var onTintOpacityChange: ((CGFloat) -> Void)?
    var onFocusSizeChange: ((CGFloat, CGFloat) -> Void)?
    var onTerminalFontChange: ((String) -> Void)?
    var onUsageFontChange: ((String) -> Void)?
    var onUsageFontSizeChange: ((CGFloat) -> Void)?
    var onUsageDisplayModeChange: ((UsageDisplayMode) -> Void)?
    var onUsageTextColorChange: ((UsageTextColor) -> Void)?
    var onReset: (() -> Void)?
    var onCancel: (() -> Void)?

    init(
        selectedPane: SettingsPaneID,
        deckConfiguration: PanelDeckConfiguration,
        cornerRadius: CGFloat,
        tintOpacity: CGFloat,
        focusWidthMultiplier: CGFloat,
        focusHeightMultiplier: CGFloat,
        fontNames: [String],
        terminalFontName: String,
        usageFontName: String,
        usageFontSize: CGFloat,
        usageDisplayMode: UsageDisplayMode,
        usageTextColor: UsageTextColor
    ) {
        self.selectedPane = selectedPane
        self.deckConfiguration = deckConfiguration.normalized()
        self.cornerRadius = cornerRadius
        self.tintOpacity = tintOpacity
        self.focusWidthMultiplier = focusWidthMultiplier
        self.focusHeightMultiplier = focusHeightMultiplier
        self.terminalFontName = terminalFontName
        self.usageFontName = usageFontName
        self.usageFontSize = usageFontSize
        self.usageDisplayMode = usageDisplayMode
        self.usageTextColor = usageTextColor

        var availableFonts = fontNames
        for selectedFont in [terminalFontName, usageFontName]
            where !availableFonts.contains(selectedFont)
        {
            availableFonts.insert(selectedFont, at: 0)
        }
        self.fontNames = availableFonts
    }

    var moduleDefinitions: [PanelModuleDefinition] {
        (deckConfiguration.left + deckConfiguration.right).compactMap {
            PanelModuleDefinition.definition(for: $0)
        }
    }

    func moduleDefinitions(on side: PanelSide) -> [PanelModuleDefinition] {
        let modules = side == .left ? deckConfiguration.left : deckConfiguration.right
        return modules.compactMap { PanelModuleDefinition.definition(for: $0) }
    }

    func side(containing module: PanelModuleID) -> PanelSide? {
        deckConfiguration.side(containing: module)
    }

    func isEnabled(_ module: PanelModuleID) -> Bool {
        deckConfiguration.contains(module)
    }

    func canDisable(_ module: PanelModuleID) -> Bool {
        !isEnabled(module)
            || moduleDefinitions.contains { $0.id != module && isEnabled($0.id) }
    }

    func selectPane(_ pane: SettingsPaneID) {
        selectedPane = pane
    }

    func setEnabled(_ enabled: Bool, for module: PanelModuleID) {
        guard enabled || canDisable(module) else { return }
        var configuration = deckConfiguration
        configuration.setEnabled(enabled, for: module)
        publish(configuration)
    }

    func swapDecks() {
        var configuration = deckConfiguration
        swap(&configuration.left, &configuration.right)
        publish(configuration)
    }

    func setCornerRadius(_ value: CGFloat) {
        cornerRadius = value.rounded()
        onCornerRadiusChange?(cornerRadius)
    }

    func setTintOpacity(_ value: CGFloat) {
        tintOpacity = (value * 100).rounded() / 100
        onTintOpacityChange?(tintOpacity)
    }

    func setFocusWidthMultiplier(_ value: CGFloat) {
        focusWidthMultiplier = (value * 4).rounded() / 4
        onFocusSizeChange?(focusWidthMultiplier, focusHeightMultiplier)
    }

    func setFocusHeightMultiplier(_ value: CGFloat) {
        focusHeightMultiplier = (value * 4).rounded() / 4
        onFocusSizeChange?(focusWidthMultiplier, focusHeightMultiplier)
    }

    func setTerminalFontName(_ value: String) {
        terminalFontName = value
        onTerminalFontChange?(value)
    }

    func setUsageFontName(_ value: String) {
        usageFontName = value
        onUsageFontChange?(value)
    }

    func setUsageFontSize(_ value: CGFloat) {
        usageFontSize = value.rounded()
        onUsageFontSizeChange?(usageFontSize)
    }

    func setUsageDisplayMode(_ value: UsageDisplayMode) {
        usageDisplayMode = value
        onUsageDisplayModeChange?(value)
    }

    func setUsageTextColor(_ value: UsageTextColor) {
        usageTextColor = value
        onUsageTextColorChange?(value)
    }

    func setValues(
        deckConfiguration: PanelDeckConfiguration,
        cornerRadius: CGFloat,
        tintOpacity: CGFloat,
        focusWidthMultiplier: CGFloat,
        focusHeightMultiplier: CGFloat,
        terminalFontName: String,
        usageFontName: String,
        usageFontSize: CGFloat,
        usageDisplayMode: UsageDisplayMode,
        usageTextColor: UsageTextColor
    ) {
        self.deckConfiguration = deckConfiguration.normalized()
        self.cornerRadius = cornerRadius
        self.tintOpacity = tintOpacity
        self.focusWidthMultiplier = focusWidthMultiplier
        self.focusHeightMultiplier = focusHeightMultiplier
        self.terminalFontName = terminalFontName
        self.usageFontName = usageFontName
        self.usageFontSize = usageFontSize
        self.usageDisplayMode = usageDisplayMode
        self.usageTextColor = usageTextColor
    }

    private func publish(_ configuration: PanelDeckConfiguration) {
        let configuration = configuration.normalized()
        deckConfiguration = configuration
        onDeckConfigurationChange?(configuration)
    }
}

final class SettingsPanelView: NSView {
    static let preferredSize = NSSize(width: 700, height: 520)

    private let model: SettingsPanelModel
    private let hostingView: NSHostingView<SettingsRootView>

    var onPaneChange: ((SettingsPaneID) -> Void)? {
        get { model.onPaneChange }
        set { model.onPaneChange = newValue }
    }
    var onDeckConfigurationChange: ((PanelDeckConfiguration) -> Void)? {
        get { model.onDeckConfigurationChange }
        set { model.onDeckConfigurationChange = newValue }
    }
    var onCornerRadiusChange: ((CGFloat) -> Void)? {
        get { model.onCornerRadiusChange }
        set { model.onCornerRadiusChange = newValue }
    }
    var onTintOpacityChange: ((CGFloat) -> Void)? {
        get { model.onTintOpacityChange }
        set { model.onTintOpacityChange = newValue }
    }
    var onFocusSizeChange: ((CGFloat, CGFloat) -> Void)? {
        get { model.onFocusSizeChange }
        set { model.onFocusSizeChange = newValue }
    }
    var onTerminalFontChange: ((String) -> Void)? {
        get { model.onTerminalFontChange }
        set { model.onTerminalFontChange = newValue }
    }
    var onUsageFontChange: ((String) -> Void)? {
        get { model.onUsageFontChange }
        set { model.onUsageFontChange = newValue }
    }
    var onUsageFontSizeChange: ((CGFloat) -> Void)? {
        get { model.onUsageFontSizeChange }
        set { model.onUsageFontSizeChange = newValue }
    }
    var onUsageDisplayModeChange: ((UsageDisplayMode) -> Void)? {
        get { model.onUsageDisplayModeChange }
        set { model.onUsageDisplayModeChange = newValue }
    }
    var onUsageTextColorChange: ((UsageTextColor) -> Void)? {
        get { model.onUsageTextColorChange }
        set { model.onUsageTextColorChange = newValue }
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
        deckConfiguration: PanelDeckConfiguration,
        cornerRadius: CGFloat,
        tintOpacity: CGFloat,
        focusWidthMultiplier: CGFloat,
        focusHeightMultiplier: CGFloat,
        fontNames: [String],
        selectedTerminalFontName: String,
        selectedUsageFontName: String,
        usageFontSize: CGFloat,
        usageDisplayMode: UsageDisplayMode,
        usageTextColor: UsageTextColor
    ) {
        let model = SettingsPanelModel(
            selectedPane: selectedPane,
            deckConfiguration: deckConfiguration,
            cornerRadius: cornerRadius,
            tintOpacity: tintOpacity,
            focusWidthMultiplier: focusWidthMultiplier,
            focusHeightMultiplier: focusHeightMultiplier,
            fontNames: fontNames,
            terminalFontName: selectedTerminalFontName,
            usageFontName: selectedUsageFontName,
            usageFontSize: usageFontSize,
            usageDisplayMode: usageDisplayMode,
            usageTextColor: usageTextColor)
        self.model = model
        hostingView = NSHostingView(rootView: SettingsRootView(model: model))

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

    func setValues(
        deckConfiguration: PanelDeckConfiguration,
        cornerRadius: CGFloat,
        tintOpacity: CGFloat,
        focusWidthMultiplier: CGFloat,
        focusHeightMultiplier: CGFloat,
        terminalFontName: String,
        usageFontName: String,
        usageFontSize: CGFloat,
        usageDisplayMode: UsageDisplayMode,
        usageTextColor: UsageTextColor
    ) {
        model.setValues(
            deckConfiguration: deckConfiguration,
            cornerRadius: cornerRadius,
            tintOpacity: tintOpacity,
            focusWidthMultiplier: focusWidthMultiplier,
            focusHeightMultiplier: focusHeightMultiplier,
            terminalFontName: terminalFontName,
            usageFontName: usageFontName,
            usageFontSize: usageFontSize,
            usageDisplayMode: usageDisplayMode,
            usageTextColor: usageTextColor)
    }

    @objc override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private struct SettingsRootView: View {
    @ObservedObject var model: SettingsPanelModel

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

                List(SettingsPaneID.allCases, selection: $model.selectedPane) { pane in
                    Label(pane.title, systemImage: pane.symbolName)
                        .tag(pane)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 184)
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            VStack(spacing: 0) {
                SettingsHeader(pane: model.selectedPane)
                Divider()
                selectedPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            minWidth: SettingsPanelView.preferredSize.width,
            minHeight: SettingsPanelView.preferredSize.height)
    }

    @ViewBuilder private var selectedPane: some View {
        switch model.selectedPane {
        case .decks:
            DecksSettingsView(model: model)
        case .terminal:
            TerminalSettingsView(model: model)
        case .usage:
            UsageSettingsView(model: model)
        case .appearance:
            AppearanceSettingsView(model: model)
        }
    }
}

private struct SettingsHeader: View {
    let pane: SettingsPaneID

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
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
    }
}

private struct DecksSettingsView: View {
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

private struct TerminalSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 14) {
                        SettingsSliderRow(
                            title: "Width",
                            valueText: String(format: "%.2f×", model.focusWidthMultiplier),
                            value: Binding(
                                get: { Double(model.focusWidthMultiplier) },
                                set: { model.setFocusWidthMultiplier(CGFloat($0)) }),
                            range: Double(DockPanelLayout.minimumFocusedWidthMultiplier)
                                ... Double(DockPanelLayout.maximumFocusedWidthMultiplier),
                            step: 0.25)
                        SettingsSliderRow(
                            title: "Height",
                            valueText: String(format: "%.2f×", model.focusHeightMultiplier),
                            value: Binding(
                                get: { Double(model.focusHeightMultiplier) },
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
                                get: { model.terminalFontName },
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

private struct UsageSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    SettingsPickerRow(title: "Values") {
                        Picker(
                            "Usage values",
                            selection: Binding(
                                get: { model.usageDisplayMode },
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
                                    get: { model.usageFontName },
                                    set: model.setUsageFontName)
                            ) {
                                ForEach(model.fontNames, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 230)
                        }
                        SettingsSliderRow(
                            title: "Size",
                            valueText: String(format: "%.0f pt", model.usageFontSize),
                            value: Binding(
                                get: { Double(model.usageFontSize) },
                                set: { model.setUsageFontSize(CGFloat($0)) }),
                            range: Double(PanelSettings.minimumUsageFontSize)
                                ... Double(PanelSettings.maximumUsageFontSize),
                            step: 1)
                        SettingsPickerRow(title: "Color") {
                            Picker(
                                "Usage text color",
                                selection: Binding(
                                    get: { model.usageTextColor },
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

private struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 14) {
                        SettingsSliderRow(
                            title: "Corner Radius",
                            valueText: String(format: "%.0f pt", model.cornerRadius),
                            value: Binding(
                                get: { Double(model.cornerRadius) },
                                set: { model.setCornerRadius(CGFloat($0)) }),
                            range: 0...24,
                            step: 1)
                        SettingsSliderRow(
                            title: "Theme Tint",
                            valueText: String(format: "%.0f%%", model.tintOpacity * 100),
                            value: Binding(
                                get: { Double(model.tintOpacity) },
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
                            Text("Restore Decks, Terminal, Usage, and Appearance defaults.")
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

private struct SettingsPickerRow<Content: View>: View {
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
