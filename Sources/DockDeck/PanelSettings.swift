import Cocoa

enum UsageDisplayMode: String, CaseIterable {
    case remaining
    case used

    var title: String {
        switch self {
        case .remaining: "Remaining"
        case .used: "Used"
        }
    }

    var accessibilityDescription: String { rawValue }

    func value(for window: UsageWindow) -> Double {
        switch self {
        case .remaining: window.remainingPercent
        case .used: min(max(window.usedPercent, 0), 100)
        }
    }
}

enum UsageTextColor: String, CaseIterable {
    case theme
    case white
    case mint
    case cyan
    case amber

    var title: String {
        switch self {
        case .theme: "Theme"
        case .white: "White"
        case .mint: "Mint"
        case .cyan: "Cyan"
        case .amber: "Amber"
        }
    }

    func color(for theme: Theme) -> NSColor {
        switch self {
        case .theme: theme.foregroundColor
        case .white: .white
        case .mint: NSColor(calibratedRed: 0.45, green: 0.95, blue: 0.70, alpha: 1)
        case .cyan: NSColor(calibratedRed: 0.35, green: 0.85, blue: 1, alpha: 1)
        case .amber: NSColor(calibratedRed: 1, green: 0.72, blue: 0.30, alpha: 1)
        }
    }
}

enum PanelOrder: String, CaseIterable {
    case terminalLeft
    case terminalRight

    var title: String {
        switch self {
        case .terminalLeft: "Terminal Left"
        case .terminalRight: "Terminal Right"
        }
    }
}

struct EnabledPanels: OptionSet {
    let rawValue: Int

    static let terminal = EnabledPanels(rawValue: 1 << 0)
    static let usage = EnabledPanels(rawValue: 1 << 1)
    static let all: EnabledPanels = [.terminal, .usage]

    static func resolved(_ panels: EnabledPanels) -> EnabledPanels {
        let knownPanels = panels.intersection(.all)
        return knownPanels.isEmpty ? .all : knownPanels
    }
}

struct PanelModuleID: Hashable, Codable {
    let rawValue: String

    static let terminal = PanelModuleID(rawValue: "terminal")
    static let usage = PanelModuleID(rawValue: "usage")

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum PanelSide: String, Codable {
    case left
    case right
}

struct PanelDeckConfiguration: Codable, Equatable {
    var left: [PanelModuleID]
    var right: [PanelModuleID]
    var enabled: [PanelModuleID]

    static func legacy(order: PanelOrder, enabledPanels: EnabledPanels) -> Self {
        let left: [PanelModuleID] = order == .terminalLeft ? [.terminal] : [.usage]
        let right: [PanelModuleID] = order == .terminalLeft ? [.usage] : [.terminal]
        var enabled: [PanelModuleID] = []
        if enabledPanels.contains(.terminal) { enabled.append(.terminal) }
        if enabledPanels.contains(.usage) { enabled.append(.usage) }
        return Self(left: left, right: right, enabled: enabled).normalized()
    }

    func side(containing module: PanelModuleID) -> PanelSide? {
        if left.contains(module) { return .left }
        if right.contains(module) { return .right }
        return nil
    }

    func contains(_ module: PanelModuleID) -> Bool {
        enabled.contains(module)
    }

    mutating func move(_ module: PanelModuleID, to side: PanelSide) {
        left.removeAll { $0 == module }
        right.removeAll { $0 == module }
        switch side {
        case .left: left.append(module)
        case .right: right.append(module)
        }
    }

    mutating func setEnabled(_ value: Bool, for module: PanelModuleID) {
        enabled.removeAll { $0 == module }
        if value { enabled.append(module) }
    }

    func normalized() -> Self {
        var seen: Set<PanelModuleID> = []
        var left = uniqueModules(self.left, seen: &seen)
        var right = uniqueModules(self.right, seen: &seen)

        if !seen.contains(.terminal) {
            left.append(.terminal)
            seen.insert(.terminal)
        }
        if !seen.contains(.usage) {
            right.append(.usage)
            seen.insert(.usage)
        }

        var enabledSeen: Set<PanelModuleID> = []
        var enabled = uniqueModules(self.enabled, seen: &enabledSeen)
        for module in enabled where !seen.contains(module) {
            right.append(module)
            seen.insert(module)
        }
        if enabled.isEmpty {
            enabled = [.terminal, .usage]
        }

        return Self(left: left, right: right, enabled: enabled)
    }

    private func uniqueModules(
        _ modules: [PanelModuleID], seen: inout Set<PanelModuleID>
    ) -> [PanelModuleID] {
        modules.filter { module in
            !module.rawValue.isEmpty && seen.insert(module).inserted
        }
    }
}

enum PanelSettings {
    static let minimumUsageFontSize: CGFloat = 8
    static let maximumUsageFontSize: CGFloat = 14
    static let defaultUsageFontSize: CGFloat = 10

    private static let cornerRadiusKey = "DockDeck.settings.cornerRadius"
    private static let tintOpacityKey = "DockDeck.settings.tintOpacity"
    private static let fontNameKey = "DockDeck.settings.fontName"
    private static let focusWidthMultiplierKey = "DockDeck.settings.focusWidthMultiplier"
    private static let focusHeightMultiplierKey = "DockDeck.settings.focusHeightMultiplier"
    private static let usageDisplayModeKey = "DockDeck.settings.usageDisplayMode"
    private static let usageFontNameKey = "DockDeck.settings.usageFontName"
    private static let usageFontSizeKey = "DockDeck.settings.usageFontSize"
    private static let usageTextColorKey = "DockDeck.settings.usageTextColor"
    private static let enabledUsageProvidersKey = "DockDeck.settings.enabledUsageProviders"
    private static let panelOrderKey = "DockDeck.settings.panelOrder"
    private static let enabledPanelsKey = "DockDeck.settings.enabledPanels"
    private static let panelDeckConfigurationKey =
        "DockDeck.settings.panelDeckConfiguration.v1"

    static var cornerRadius: CGFloat {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: cornerRadiusKey) != nil else {
                return TerminalTheme.defaultCornerRadius
            }
            return CGFloat(defaults.double(forKey: cornerRadiusKey))
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: cornerRadiusKey) }
    }

    static var tintOpacity: CGFloat? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: tintOpacityKey) != nil else { return nil }
            return CGFloat(defaults.double(forKey: tintOpacityKey))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(Double(newValue), forKey: tintOpacityKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tintOpacityKey)
            }
        }
    }

    static var fontName: String? {
        get { UserDefaults.standard.string(forKey: fontNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: fontNameKey) }
    }

    static var usageDisplayMode: UsageDisplayMode {
        get {
            UserDefaults.standard.string(forKey: usageDisplayModeKey)
                .flatMap(UsageDisplayMode.init(rawValue:)) ?? .remaining
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: usageDisplayModeKey) }
    }

    static var usageFontName: String? {
        get { UserDefaults.standard.string(forKey: usageFontNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: usageFontNameKey) }
    }

    static var usageFontSize: CGFloat {
        get {
            let defaults = UserDefaults.standard
            let value = defaults.object(forKey: usageFontSizeKey) == nil
                ? defaultUsageFontSize
                : CGFloat(defaults.double(forKey: usageFontSizeKey))
            return min(max(value, minimumUsageFontSize), maximumUsageFontSize)
        }
        set {
            let value = min(max(newValue, minimumUsageFontSize), maximumUsageFontSize)
            UserDefaults.standard.set(Double(value), forKey: usageFontSizeKey)
        }
    }

    static var usageTextColor: UsageTextColor {
        get {
            UserDefaults.standard.string(forKey: usageTextColorKey)
                .flatMap(UsageTextColor.init(rawValue:)) ?? .theme
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: usageTextColorKey) }
    }

    static var enabledUsageProviders: [UsageProviderID] {
        get {
            guard let stored = UserDefaults.standard.stringArray(forKey: enabledUsageProvidersKey)
            else { return UsageProviderID.allCases }
            let selected = Set(stored.compactMap(UsageProviderID.init(rawValue:)))
            let providers = UsageProviderID.allCases.filter(selected.contains)
            return providers.isEmpty ? UsageProviderID.allCases : providers
        }
        set {
            let selected = Set(newValue)
            let providers = UsageProviderID.allCases.filter(selected.contains)
            let resolved = providers.isEmpty ? UsageProviderID.allCases : providers
            UserDefaults.standard.set(resolved.map(\.rawValue), forKey: enabledUsageProvidersKey)
        }
    }

    static var panelOrder: PanelOrder {
        get {
            deckConfiguration.side(containing: .terminal) == .right
                ? .terminalRight : .terminalLeft
        }
        set {
            var configuration = deckConfiguration
            configuration.move(
                .terminal, to: newValue == .terminalLeft ? .left : .right)
            configuration.move(
                .usage, to: newValue == .terminalLeft ? .right : .left)
            deckConfiguration = configuration
        }
    }

    static var enabledPanels: EnabledPanels {
        get {
            var panels: EnabledPanels = []
            if deckConfiguration.contains(.terminal) { panels.insert(.terminal) }
            if deckConfiguration.contains(.usage) { panels.insert(.usage) }
            return panels
        }
        set {
            let resolved = EnabledPanels.resolved(newValue)
            var configuration = deckConfiguration
            configuration.setEnabled(resolved.contains(.terminal), for: .terminal)
            configuration.setEnabled(resolved.contains(.usage), for: .usage)
            deckConfiguration = configuration
        }
    }

    static var deckConfiguration: PanelDeckConfiguration {
        get {
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: panelDeckConfigurationKey),
                let configuration = try? JSONDecoder().decode(
                    PanelDeckConfiguration.self, from: data)
            {
                return configuration.normalized()
            }
            return legacyDeckConfiguration(defaults: defaults)
        }
        set { persistDeckConfiguration(newValue.normalized(), defaults: .standard) }
    }

    static func migratePanelDeckIfNeeded() {
        let defaults = UserDefaults.standard
        guard
            defaults.data(forKey: panelDeckConfigurationKey).flatMap({
                try? JSONDecoder().decode(PanelDeckConfiguration.self, from: $0)
            }) == nil
        else { return }
        persistDeckConfiguration(legacyDeckConfiguration(defaults: defaults), defaults: defaults)
    }

    static var focusWidthMultiplier: CGFloat {
        get {
            let defaults = UserDefaults.standard
            let value = defaults.object(forKey: focusWidthMultiplierKey) == nil
                ? DockPanelLayout.focusedWidthMultiplier
                : CGFloat(defaults.double(forKey: focusWidthMultiplierKey))
            return min(
                max(value, DockPanelLayout.minimumFocusedWidthMultiplier),
                DockPanelLayout.maximumFocusedWidthMultiplier)
        }
        set {
            let value = min(
                max(newValue, DockPanelLayout.minimumFocusedWidthMultiplier),
                DockPanelLayout.maximumFocusedWidthMultiplier)
            UserDefaults.standard.set(Double(value), forKey: focusWidthMultiplierKey)
        }
    }

    static var focusHeightMultiplier: CGFloat {
        get {
            let defaults = UserDefaults.standard
            let value = defaults.object(forKey: focusHeightMultiplierKey) == nil
                ? DockPanelLayout.focusedHeightMultiplier
                : CGFloat(defaults.double(forKey: focusHeightMultiplierKey))
            return min(
                max(value, DockPanelLayout.minimumFocusedHeightMultiplier),
                DockPanelLayout.maximumFocusedHeightMultiplier)
        }
        set {
            let value = min(
                max(newValue, DockPanelLayout.minimumFocusedHeightMultiplier),
                DockPanelLayout.maximumFocusedHeightMultiplier)
            UserDefaults.standard.set(Double(value), forKey: focusHeightMultiplierKey)
        }
    }

    static func resetToDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: cornerRadiusKey)
        defaults.removeObject(forKey: tintOpacityKey)
        defaults.removeObject(forKey: fontNameKey)
        defaults.removeObject(forKey: focusWidthMultiplierKey)
        defaults.removeObject(forKey: focusHeightMultiplierKey)
        defaults.removeObject(forKey: usageDisplayModeKey)
        defaults.removeObject(forKey: usageFontNameKey)
        defaults.removeObject(forKey: usageFontSizeKey)
        defaults.removeObject(forKey: usageTextColorKey)
        defaults.removeObject(forKey: enabledUsageProvidersKey)
        defaults.removeObject(forKey: panelOrderKey)
        defaults.removeObject(forKey: enabledPanelsKey)
        defaults.removeObject(forKey: panelDeckConfigurationKey)
    }

    private static func legacyDeckConfiguration(
        defaults: UserDefaults
    ) -> PanelDeckConfiguration {
        let order = defaults.string(forKey: panelOrderKey)
            .flatMap(PanelOrder.init(rawValue:)) ?? .terminalLeft
        let enabledPanels: EnabledPanels
        if defaults.object(forKey: enabledPanelsKey) == nil {
            enabledPanels = .all
        } else {
            enabledPanels = .resolved(
                EnabledPanels(rawValue: defaults.integer(forKey: enabledPanelsKey)))
        }
        return .legacy(order: order, enabledPanels: enabledPanels)
    }

    private static func persistDeckConfiguration(
        _ configuration: PanelDeckConfiguration, defaults: UserDefaults
    ) {
        let configuration = configuration.normalized()
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: panelDeckConfigurationKey)

        let order: PanelOrder = configuration.side(containing: .terminal) == .right
            ? .terminalRight : .terminalLeft
        var enabledPanels: EnabledPanels = []
        if configuration.contains(.terminal) { enabledPanels.insert(.terminal) }
        if configuration.contains(.usage) { enabledPanels.insert(.usage) }
        defaults.set(order.rawValue, forKey: panelOrderKey)
        defaults.set(EnabledPanels.resolved(enabledPanels).rawValue, forKey: enabledPanelsKey)
    }
}
