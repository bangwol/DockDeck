import Cocoa
import Combine

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
    let settingsPane: SettingsPaneID?
}

enum PanelModuleRegistry {
    static let all = [
        PanelModuleDefinition(
            id: .terminal, title: "Terminal", subtitle: "Interactive login shell",
            symbolName: "terminal", settingsPane: .terminal),
        PanelModuleDefinition(
            id: .usage, title: "Usage", subtitle: "Codex and Claude limits",
            symbolName: "chart.bar", settingsPane: .usage),
    ]

    static func definition(for id: PanelModuleID) -> PanelModuleDefinition? {
        all.first { $0.id == id }
    }

    static func definition(for settingsPane: SettingsPaneID) -> PanelModuleDefinition? {
        all.first { $0.settingsPane == settingsPane }
    }
}

struct TerminalSettingsState: Equatable {
    var focusWidthMultiplier: CGFloat
    var focusHeightMultiplier: CGFloat
    var fontName: String
}

struct UsageSettingsState: Equatable {
    var enabledProviders: [UsageProviderID]
    var fontName: String
    var fontSize: CGFloat
    var displayMode: UsageDisplayMode
    var textColor: UsageTextColor
}

struct AppearanceSettingsState: Equatable {
    var cornerRadius: CGFloat
    var tintOpacity: CGFloat
}

struct SettingsPanelValues: Equatable {
    var deckConfiguration: PanelDeckConfiguration
    var terminal: TerminalSettingsState
    var usage: UsageSettingsState
    var appearance: AppearanceSettingsState

    func normalized() -> Self {
        var values = self
        values.deckConfiguration = deckConfiguration.normalized()
        return values
    }
}

enum TerminalSettingsChange {
    case focusSize(width: CGFloat, height: CGFloat)
    case font(String)
}

enum UsageSettingsChange {
    case providers([UsageProviderID])
    case displayMode(UsageDisplayMode)
    case font(String)
    case fontSize(CGFloat)
    case textColor(UsageTextColor)
}

enum AppearanceSettingsChange {
    case cornerRadius(CGFloat)
    case tintOpacity(CGFloat)
}

enum SettingsPanelChange {
    case deck(PanelDeckConfiguration)
    case terminal(TerminalSettingsChange)
    case usage(UsageSettingsChange)
    case appearance(AppearanceSettingsChange)
}

final class SettingsPanelModel: ObservableObject {
    @Published var selectedPane: SettingsPaneID {
        didSet { onPaneChange?(selectedPane) }
    }
    @Published private(set) var values: SettingsPanelValues

    let fontNames: [String]

    var onPaneChange: ((SettingsPaneID) -> Void)?
    var onChange: ((SettingsPanelChange) -> Void)?
    var onReset: (() -> Void)?
    var onCancel: (() -> Void)?

    init(
        selectedPane: SettingsPaneID,
        values: SettingsPanelValues,
        fontNames: [String]
    ) {
        let values = values.normalized()
        self.values = values

        var availableFonts = fontNames
        for selectedFont in [values.terminal.fontName, values.usage.fontName]
            where !availableFonts.contains(selectedFont)
        {
            availableFonts.insert(selectedFont, at: 0)
        }
        self.fontNames = availableFonts

        let modulePanes = Self.moduleDefinitions(in: values.deckConfiguration)
            .compactMap(\.settingsPane)
        self.selectedPane = modulePanes.contains(selectedPane)
            || selectedPane == .decks || selectedPane == .appearance
            ? selectedPane : .decks
    }

    var moduleDefinitions: [PanelModuleDefinition] {
        Self.moduleDefinitions(in: values.deckConfiguration)
    }

    var availablePanes: [SettingsPaneID] {
        var panes: [SettingsPaneID] = [.decks]
        for pane in moduleDefinitions.compactMap(\.settingsPane) where !panes.contains(pane) {
            panes.append(pane)
        }
        if !panes.contains(.appearance) { panes.append(.appearance) }
        return panes
    }

    func moduleDefinitions(on side: PanelSide) -> [PanelModuleDefinition] {
        let modules = side == .left
            ? values.deckConfiguration.left : values.deckConfiguration.right
        return modules.compactMap { PanelModuleRegistry.definition(for: $0) }
    }

    func side(containing module: PanelModuleID) -> PanelSide? {
        values.deckConfiguration.side(containing: module)
    }

    func isEnabled(_ module: PanelModuleID) -> Bool {
        values.deckConfiguration.contains(module)
    }

    func moduleDefinition(for pane: SettingsPaneID) -> PanelModuleDefinition? {
        PanelModuleRegistry.definition(for: pane)
    }

    func canDisable(_ module: PanelModuleID) -> Bool {
        !isEnabled(module)
            || moduleDefinitions.contains { $0.id != module && isEnabled($0.id) }
    }

    func selectPane(_ pane: SettingsPaneID) {
        guard availablePanes.contains(pane) else { return }
        selectedPane = pane
    }

    func setEnabled(_ enabled: Bool, for module: PanelModuleID) {
        guard enabled || canDisable(module) else { return }
        var configuration = values.deckConfiguration
        configuration.setEnabled(enabled, for: module)
        publishDeck(configuration)
    }

    func swapDecks() {
        var configuration = values.deckConfiguration
        swap(&configuration.left, &configuration.right)
        publishDeck(configuration)
    }

    func setCornerRadius(_ value: CGFloat) {
        let value = value.rounded()
        updateValues { $0.appearance.cornerRadius = value }
        onChange?(.appearance(.cornerRadius(value)))
    }

    func setTintOpacity(_ value: CGFloat) {
        let value = (value * 100).rounded() / 100
        updateValues { $0.appearance.tintOpacity = value }
        onChange?(.appearance(.tintOpacity(value)))
    }

    func setFocusWidthMultiplier(_ value: CGFloat) {
        let value = (value * 4).rounded() / 4
        updateValues { $0.terminal.focusWidthMultiplier = value }
        publishFocusSize()
    }

    func setFocusHeightMultiplier(_ value: CGFloat) {
        let value = (value * 4).rounded() / 4
        updateValues { $0.terminal.focusHeightMultiplier = value }
        publishFocusSize()
    }

    func setTerminalFontName(_ value: String) {
        updateValues { $0.terminal.fontName = value }
        onChange?(.terminal(.font(value)))
    }

    func setUsageFontName(_ value: String) {
        updateValues { $0.usage.fontName = value }
        onChange?(.usage(.font(value)))
    }

    func isUsageProviderEnabled(_ provider: UsageProviderID) -> Bool {
        values.usage.enabledProviders.contains(provider)
    }

    func canDisableUsageProvider(_ provider: UsageProviderID) -> Bool {
        !isUsageProviderEnabled(provider) || values.usage.enabledProviders.count > 1
    }

    func setUsageProvider(_ provider: UsageProviderID, enabled: Bool) {
        guard enabled || canDisableUsageProvider(provider) else { return }
        var providers = values.usage.enabledProviders.filter { $0 != provider }
        if enabled { providers.append(provider) }
        providers = UsageProviderID.allCases.filter(Set(providers).contains)
        updateValues { $0.usage.enabledProviders = providers }
        onChange?(.usage(.providers(providers)))
    }

    func setUsageFontSize(_ value: CGFloat) {
        let value = value.rounded()
        updateValues { $0.usage.fontSize = value }
        onChange?(.usage(.fontSize(value)))
    }

    func setUsageDisplayMode(_ value: UsageDisplayMode) {
        updateValues { $0.usage.displayMode = value }
        onChange?(.usage(.displayMode(value)))
    }

    func setUsageTextColor(_ value: UsageTextColor) {
        updateValues { $0.usage.textColor = value }
        onChange?(.usage(.textColor(value)))
    }

    func setValues(_ values: SettingsPanelValues) {
        self.values = values.normalized()
        if !availablePanes.contains(selectedPane) { selectedPane = .decks }
    }

    private static func moduleDefinitions(
        in configuration: PanelDeckConfiguration
    ) -> [PanelModuleDefinition] {
        (configuration.left + configuration.right).compactMap {
            PanelModuleRegistry.definition(for: $0)
        }
    }

    private func updateValues(_ update: (inout SettingsPanelValues) -> Void) {
        var values = self.values
        update(&values)
        self.values = values
    }

    private func publishDeck(_ configuration: PanelDeckConfiguration) {
        let configuration = configuration.normalized()
        updateValues { $0.deckConfiguration = configuration }
        onChange?(.deck(configuration))
    }

    private func publishFocusSize() {
        onChange?(
            .terminal(
                .focusSize(
                    width: values.terminal.focusWidthMultiplier,
                    height: values.terminal.focusHeightMultiplier)))
    }
}
