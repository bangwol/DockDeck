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
enum ClaudeUsageRefreshMode: String, CaseIterable {
    case automatic
    case statusLineOnly

    var title: String {
        switch self {
        case .automatic: "Automatic /usage"
        case .statusLineOnly: "Status line only"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic:
            "Refresh at launch, on demand, after wake, and every 10–20 minutes."
        case .statusLineOnly:
            "Never launch Claude in the background; update after Claude responses."
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

struct DockNotificationSettings: Codable, Equatable {
    static let usageThresholds = [10, 20, 30]
    static let batteryThresholds = [10, 20, 30]

    var enabled = false
    var usageAlerts = true
    var usageRemainingThreshold = 20
    var serviceFailureAlerts = true
    var serviceRecoveryAlerts = true
    var batteryAlerts = true
    var batteryRemainingThreshold = 20
    var systemThermalAlerts = false
    var focusTimerAlerts = true

    func normalized() -> Self {
        var settings = self
        settings.usageRemainingThreshold = Self.closest(
            usageRemainingThreshold, in: Self.usageThresholds)
        settings.batteryRemainingThreshold = Self.closest(
            batteryRemainingThreshold, in: Self.batteryThresholds)
        return settings
    }

    private static func closest(_ value: Int, in options: [Int]) -> Int {
        options.min { abs($0 - value) < abs($1 - value) } ?? options[0]
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case usageAlerts
        case usageRemainingThreshold
        case serviceFailureAlerts
        case serviceRecoveryAlerts
        case batteryAlerts
        case batteryRemainingThreshold
        case systemThermalAlerts
        case focusTimerAlerts
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        usageAlerts = try values.decodeIfPresent(Bool.self, forKey: .usageAlerts) ?? true
        usageRemainingThreshold = try values.decodeIfPresent(
            Int.self, forKey: .usageRemainingThreshold) ?? 20
        serviceFailureAlerts = try values.decodeIfPresent(
            Bool.self, forKey: .serviceFailureAlerts) ?? true
        serviceRecoveryAlerts = try values.decodeIfPresent(
            Bool.self, forKey: .serviceRecoveryAlerts) ?? true
        batteryAlerts = try values.decodeIfPresent(Bool.self, forKey: .batteryAlerts) ?? true
        batteryRemainingThreshold = try values.decodeIfPresent(
            Int.self, forKey: .batteryRemainingThreshold) ?? 20
        systemThermalAlerts = try values.decodeIfPresent(
            Bool.self, forKey: .systemThermalAlerts) ?? false
        focusTimerAlerts = try values.decodeIfPresent(
            Bool.self, forKey: .focusTimerAlerts) ?? true
        self = normalized()
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
    static let battery = PanelModuleID(rawValue: "battery")
    static let network = PanelModuleID(rawValue: "network")
    static let projectPulse = PanelModuleID(rawValue: "project-pulse")
    static let githubInbox = PanelModuleID(rawValue: "github-inbox")
    static let docker = PanelModuleID(rawValue: "docker")
    static let customTile = PanelModuleID(rawValue: "custom-tile")
    static let focusTimer = PanelModuleID(rawValue: "focus-timer")

    static let readOnlyBuiltIns: [PanelModuleID] = [
        .usage, .systemStats, .serviceMonitor, .weather, .schedule, .clock, .battery,
        .network,
        .projectPulse,
        .githubInbox,
        .docker,
        .customTile,
        .focusTimer,
    ]
    static let builtIns: [PanelModuleID] = [.terminal] + readOnlyBuiltIns

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

enum PanelSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: Self { self }
    var opposite: Self { self == .left ? .right : .left }
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

    func modules(on side: PanelSide) -> [PanelModuleID] {
        side == .left ? left : right
    }

    func enabledModules(on side: PanelSide) -> [PanelModuleID] {
        let enabled = Set(enabled)
        return modules(on: side).filter(enabled.contains)
    }

    func contains(_ module: PanelModuleID) -> Bool {
        enabled.contains(module)
    }

    mutating func setEnabled(_ value: Bool, for module: PanelModuleID) {
        enabled.removeAll { $0 == module }
        if value { enabled.append(module) }
    }

    mutating func move(_ module: PanelModuleID, to side: PanelSide, at index: Int) {
        guard left.contains(module) || right.contains(module) else { return }
        left.removeAll { $0 == module }
        right.removeAll { $0 == module }

        switch side {
        case .left:
            left.insert(module, at: min(max(index, 0), left.count))
        case .right:
            right.insert(module, at: min(max(index, 0), right.count))
        }
        self = normalized()
    }

    func normalized() -> Self {
        var seen: Set<PanelModuleID> = []
        var left = uniqueModules(self.left, seen: &seen)
        var right = uniqueModules(self.right, seen: &seen)

        if !seen.contains(.terminal) {
            left.append(.terminal)
            seen.insert(.terminal)
        }
        let defaultReadOnlySide: PanelSide = left.contains(.terminal) ? .right : .left
        for module in PanelModuleID.readOnlyBuiltIns where !seen.contains(module) {
            switch defaultReadOnlySide {
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

        let enabledSet = Set(enabled)
        left = stableEnabledFirst(left, enabled: enabledSet)
        right = stableEnabledFirst(right, enabled: enabledSet)

        return Self(left: left, right: right, enabled: enabled)
    }

    private func stableEnabledFirst(
        _ modules: [PanelModuleID], enabled: Set<PanelModuleID>
    ) -> [PanelModuleID] {
        modules.filter(enabled.contains) + modules.filter { !enabled.contains($0) }
    }

    private func uniqueModules(
        _ modules: [PanelModuleID], seen: inout Set<PanelModuleID>
    ) -> [PanelModuleID] {
        modules.filter { module in
            !module.rawValue.isEmpty && seen.insert(module).inserted
        }
    }
}

struct DeckAutoSlideSettings: Codable, Equatable {
    static let minimumInterval: TimeInterval = 5
    static let maximumInterval: TimeInterval = 300
    static let defaultInterval: TimeInterval = 10

    var modules: [PanelModuleID]
    var interval: TimeInterval

    init(modules: [PanelModuleID] = [], interval: TimeInterval = defaultInterval) {
        self.modules = modules
        self.interval = interval
        self = normalized()
    }

    func contains(_ module: PanelModuleID) -> Bool {
        modules.contains(module)
    }

    func modules(
        on side: PanelSide, configuration: PanelDeckConfiguration
    ) -> [PanelModuleID] {
        let selected = Set(modules)
        return configuration.enabledModules(on: side).filter(selected.contains)
    }

    mutating func setEnabled(_ enabled: Bool, for module: PanelModuleID) {
        modules.removeAll { $0 == module }
        if enabled { modules.append(module) }
        self = normalized()
    }

    func normalized() -> Self {
        var seen: Set<PanelModuleID> = []
        let modules = modules.filter {
            !$0.rawValue.isEmpty && seen.insert($0).inserted
        }.prefix(100)
        let interval = interval.isFinite ? interval.rounded() : Self.defaultInterval
        return Self(
            normalizedModules: Array(modules),
            interval: min(max(interval, Self.minimumInterval), Self.maximumInterval))
    }

    private init(normalizedModules: [PanelModuleID], interval: TimeInterval) {
        modules = normalizedModules
        self.interval = interval
    }

    private enum CodingKeys: String, CodingKey {
        case modules
        case interval
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            modules: try values.decodeIfPresent([PanelModuleID].self, forKey: .modules) ?? [],
            interval: try values.decodeIfPresent(TimeInterval.self, forKey: .interval)
                ?? Self.defaultInterval)
    }
}

struct DeckAutoSlideStep: Equatable {
    let side: PanelSide
    let module: PanelModuleID
}

enum DeckAutoSlidePlanner {
    static func steps(
        settings: DeckAutoSlideSettings,
        configuration: PanelDeckConfiguration,
        activeModule: (PanelSide) -> PanelModuleID?
    ) -> [DeckAutoSlideStep] {
        PanelSide.allCases.compactMap { side in
            let candidates = settings.modules(on: side, configuration: configuration)
            guard candidates.count > 1,
                let active = activeModule(side),
                candidates.contains(active),
                let next = ReadOnlyDeckSelection.next(
                    after: active, enabledModules: candidates),
                next != active
            else { return nil }
            return DeckAutoSlideStep(side: side, module: next)
        }
    }
}
