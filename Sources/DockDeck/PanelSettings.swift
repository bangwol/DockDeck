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
    private static let panelOrderKey = "DockDeck.settings.panelOrder"

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

    static var panelOrder: PanelOrder {
        get {
            UserDefaults.standard.string(forKey: panelOrderKey)
                .flatMap(PanelOrder.init(rawValue:)) ?? .terminalLeft
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: panelOrderKey) }
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
        defaults.removeObject(forKey: panelOrderKey)
    }
}
