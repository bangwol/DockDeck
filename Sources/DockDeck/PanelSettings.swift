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
    static let systemStats = PanelModuleID(rawValue: "system-stats")
    static let serviceMonitor = PanelModuleID(rawValue: "service-monitor")
    static let weather = PanelModuleID(rawValue: "weather")
    static let schedule = PanelModuleID(rawValue: "schedule")
    static let clock = PanelModuleID(rawValue: "clock")

    static let readOnlyBuiltIns: [PanelModuleID] = [
        .usage, .systemStats, .serviceMonitor, .weather, .schedule, .clock,
    ]

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

        let readOnlySide: PanelSide = left.contains(.terminal) ? .right : .left
        left.removeAll { PanelModuleID.readOnlyBuiltIns.contains($0) }
        right.removeAll { PanelModuleID.readOnlyBuiltIns.contains($0) }
        for module in PanelModuleID.readOnlyBuiltIns {
            switch readOnlySide {
            case .left: left.append(module)
            case .right: right.append(module)
            }
            seen.insert(module)
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
    static let defaultSystemStatsRefreshInterval: TimeInterval = 2
    static let systemStatsRefreshIntervals: [TimeInterval] = [1, 2, 5, 10]
    static let defaultServiceMonitorRefreshInterval: TimeInterval = 30
    static let serviceMonitorRefreshIntervals: [TimeInterval] = [15, 30, 60, 120]
    static let defaultWeatherRefreshInterval: TimeInterval = 30 * 60
    static let weatherRefreshIntervals: [TimeInterval] = [15 * 60, 30 * 60, 60 * 60]
    static let defaultScheduleRefreshInterval: TimeInterval = 5 * 60
    static let scheduleRefreshIntervals: [TimeInterval] = [60, 5 * 60, 15 * 60]

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
    private static let systemStatsRefreshIntervalKey =
        "DockDeck.settings.systemStatsRefreshInterval"
    private static let activeReadOnlyModuleKey = "DockDeck.settings.activeReadOnlyModule"
    private static let serviceMonitorEndpointsKey = "DockDeck.settings.serviceMonitorEndpoints"
    private static let serviceMonitorRefreshIntervalKey =
        "DockDeck.settings.serviceMonitorRefreshInterval"
    private static let weatherLocationKey = "DockDeck.settings.weatherLocation"
    private static let weatherTemperatureUnitKey = "DockDeck.settings.weatherTemperatureUnit"
    private static let weatherRefreshIntervalKey = "DockDeck.settings.weatherRefreshInterval"
    private static let scheduleCalendarIDsKey = "DockDeck.settings.scheduleCalendarIDs"
    private static let scheduleIncludesAllDayKey = "DockDeck.settings.scheduleIncludesAllDay"
    private static let scheduleRefreshIntervalKey = "DockDeck.settings.scheduleRefreshInterval"
    private static let clockTimeZoneIdentifierKey =
        "DockDeck.settings.clockTimeZoneIdentifier"
    private static let clockHourFormatKey = "DockDeck.settings.clockHourFormat"
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
            let terminalIsLeft = configuration.side(containing: .terminal) != .right
            guard terminalIsLeft != (newValue == .terminalLeft) else { return }
            swap(&configuration.left, &configuration.right)
            deckConfiguration = configuration
        }
    }

    static var enabledReadOnlyModules: [PanelModuleID] {
        let configuration = deckConfiguration
        let enabled = Set(configuration.enabled)
        let known = Set(PanelModuleID.readOnlyBuiltIns)
        return (configuration.left + configuration.right).filter {
            known.contains($0) && enabled.contains($0)
        }
    }

    static var activeReadOnlyModule: PanelModuleID? {
        get {
            let preferred = UserDefaults.standard.string(forKey: activeReadOnlyModuleKey)
                .map(PanelModuleID.init(rawValue:))
            return ReadOnlyDeckSelection.resolved(
                preferred: preferred, enabledModules: enabledReadOnlyModules)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: activeReadOnlyModuleKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeReadOnlyModuleKey)
            }
        }
    }

    static var systemStatsRefreshInterval: TimeInterval {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: systemStatsRefreshIntervalKey) != nil else {
                return defaultSystemStatsRefreshInterval
            }
            let value = defaults.double(forKey: systemStatsRefreshIntervalKey)
            return systemStatsRefreshIntervals.min(by: {
                abs($0 - value) < abs($1 - value)
            }) ?? defaultSystemStatsRefreshInterval
        }
        set {
            let value = systemStatsRefreshIntervals.min(by: {
                abs($0 - newValue) < abs($1 - newValue)
            }) ?? defaultSystemStatsRefreshInterval
            UserDefaults.standard.set(value, forKey: systemStatsRefreshIntervalKey)
        }
    }

    static var serviceMonitorEndpoints: [ServiceMonitorEndpoint] {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: serviceMonitorEndpointsKey),
                let endpoints = try? JSONDecoder().decode(
                    [ServiceMonitorEndpoint].self, from: data)
            else { return [] }
            return normalizedServiceMonitorEndpoints(endpoints)
        }
        set {
            let endpoints = normalizedServiceMonitorEndpoints(newValue)
            guard let data = try? JSONEncoder().encode(endpoints) else { return }
            UserDefaults.standard.set(data, forKey: serviceMonitorEndpointsKey)
        }
    }

    static var serviceMonitorRefreshInterval: TimeInterval {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: serviceMonitorRefreshIntervalKey) != nil else {
                return defaultServiceMonitorRefreshInterval
            }
            let value = defaults.double(forKey: serviceMonitorRefreshIntervalKey)
            return serviceMonitorRefreshIntervals.min(by: {
                abs($0 - value) < abs($1 - value)
            }) ?? defaultServiceMonitorRefreshInterval
        }
        set {
            let value = serviceMonitorRefreshIntervals.min(by: {
                abs($0 - newValue) < abs($1 - newValue)
            }) ?? defaultServiceMonitorRefreshInterval
            UserDefaults.standard.set(value, forKey: serviceMonitorRefreshIntervalKey)
        }
    }

    static var weatherLocation: WeatherLocation? {
        get {
            guard let data = UserDefaults.standard.data(forKey: weatherLocationKey),
                let location = try? JSONDecoder().decode(WeatherLocation.self, from: data)
            else { return nil }
            return location.normalizedForStorage()
        }
        set {
            guard let location = newValue?.normalizedForStorage(),
                let data = try? JSONEncoder().encode(location)
            else {
                UserDefaults.standard.removeObject(forKey: weatherLocationKey)
                return
            }
            UserDefaults.standard.set(data, forKey: weatherLocationKey)
        }
    }

    static var weatherTemperatureUnit: WeatherTemperatureUnit {
        get {
            UserDefaults.standard.string(forKey: weatherTemperatureUnitKey)
                .flatMap(WeatherTemperatureUnit.init(rawValue:)) ?? .celsius
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: weatherTemperatureUnitKey) }
    }

    static var weatherRefreshInterval: TimeInterval {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: weatherRefreshIntervalKey) != nil else {
                return defaultWeatherRefreshInterval
            }
            let value = defaults.double(forKey: weatherRefreshIntervalKey)
            return weatherRefreshIntervals.min(by: {
                abs($0 - value) < abs($1 - value)
            }) ?? defaultWeatherRefreshInterval
        }
        set {
            let value = weatherRefreshIntervals.min(by: {
                abs($0 - newValue) < abs($1 - newValue)
            }) ?? defaultWeatherRefreshInterval
            UserDefaults.standard.set(value, forKey: weatherRefreshIntervalKey)
        }
    }

    static var scheduleCalendarIDs: [String] {
        get {
            normalizedScheduleCalendarIDs(
                UserDefaults.standard.stringArray(forKey: scheduleCalendarIDsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(
                normalizedScheduleCalendarIDs(newValue), forKey: scheduleCalendarIDsKey)
        }
    }

    static var scheduleIncludesAllDay: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: scheduleIncludesAllDayKey) != nil else { return false }
            return defaults.bool(forKey: scheduleIncludesAllDayKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: scheduleIncludesAllDayKey) }
    }

    static var scheduleRefreshInterval: TimeInterval {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: scheduleRefreshIntervalKey) != nil else {
                return defaultScheduleRefreshInterval
            }
            let value = defaults.double(forKey: scheduleRefreshIntervalKey)
            return scheduleRefreshIntervals.min(by: {
                abs($0 - value) < abs($1 - value)
            }) ?? defaultScheduleRefreshInterval
        }
        set {
            let value = scheduleRefreshIntervals.min(by: {
                abs($0 - newValue) < abs($1 - newValue)
            }) ?? defaultScheduleRefreshInterval
            UserDefaults.standard.set(value, forKey: scheduleRefreshIntervalKey)
        }
    }

    static var clockTimeZoneIdentifier: String {
        get {
            ClockTimeZone.normalized(
                identifier: UserDefaults.standard.string(forKey: clockTimeZoneIdentifierKey)
                    ?? ClockTimeZone.systemIdentifier)
        }
        set {
            UserDefaults.standard.set(
                ClockTimeZone.normalized(identifier: newValue),
                forKey: clockTimeZoneIdentifierKey)
        }
    }

    static var clockHourFormat: ClockHourFormat {
        get {
            UserDefaults.standard.string(forKey: clockHourFormatKey)
                .flatMap(ClockHourFormat.init(rawValue:)) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: clockHourFormatKey) }
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
        defaults.removeObject(forKey: systemStatsRefreshIntervalKey)
        defaults.removeObject(forKey: activeReadOnlyModuleKey)
        defaults.removeObject(forKey: serviceMonitorEndpointsKey)
        defaults.removeObject(forKey: serviceMonitorRefreshIntervalKey)
        defaults.removeObject(forKey: weatherLocationKey)
        defaults.removeObject(forKey: weatherTemperatureUnitKey)
        defaults.removeObject(forKey: weatherRefreshIntervalKey)
        defaults.removeObject(forKey: scheduleCalendarIDsKey)
        defaults.removeObject(forKey: scheduleIncludesAllDayKey)
        defaults.removeObject(forKey: scheduleRefreshIntervalKey)
        defaults.removeObject(forKey: clockTimeZoneIdentifierKey)
        defaults.removeObject(forKey: clockHourFormatKey)
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

    private static func normalizedServiceMonitorEndpoints(
        _ endpoints: [ServiceMonitorEndpoint]
    ) -> [ServiceMonitorEndpoint] {
        var seen: Set<UUID> = []
        var result: [ServiceMonitorEndpoint] = []
        for endpoint in endpoints {
            let endpoint = endpoint.normalizedForStorage()
            guard seen.insert(endpoint.id).inserted else { continue }
            result.append(endpoint)
            if result.count == ServiceMonitorEndpoint.maximumCount { break }
        }
        return result
    }

    private static func normalizedScheduleCalendarIDs(_ identifiers: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in identifiers {
            let value = String(
                value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count == 100 { break }
        }
        return result
    }
}
