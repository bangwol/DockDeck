import Cocoa

enum PanelSettings {
    private static let cornerRadiusKey = "DockDeck.settings.cornerRadius"
    private static let tintOpacityKey = "DockDeck.settings.tintOpacity"
    private static let fontNameKey = "DockDeck.settings.fontName"
    private static let focusWidthMultiplierKey = "DockDeck.settings.focusWidthMultiplier"
    private static let focusHeightMultiplierKey = "DockDeck.settings.focusHeightMultiplier"

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
    }
}
