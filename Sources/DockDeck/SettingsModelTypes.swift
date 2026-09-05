import Cocoa
import Combine

enum SettingsPaneID: String, CaseIterable, Identifiable {
    case decks
    case quickActions
    case notifications
    case diagnostics
    case terminal
    case usage
    case systemStats
    case serviceMonitor
    case weather
    case schedule
    case clock
    case music
    case battery
    case localPorts
    case projectPulse
    case githubInbox
    case docker
    case customTile
    case customTile2
    case customTile3
    case focusTimer
    case appearance

    var id: Self { self }

    var title: String {
        switch self {
        case .quickActions: "Quick Actions"
        case .decks: "Decks"
        case .notifications: "Notifications"
        case .diagnostics: "Diagnostics"
        case .terminal: "Terminal"
        case .usage: "Usage"
        case .systemStats: "System Stats"
        case .serviceMonitor: "Service Monitor"
        case .weather: "Weather"
        case .schedule: "Schedule"
        case .clock: "World Clock"
        case .music: "Music"
        case .battery: "Battery"
        case .localPorts: "Local Ports"
        case .projectPulse: "Project Pulse"
        case .githubInbox: "GitHub Inbox"
        case .docker: "Docker"
        case .customTile: "Custom Tile"
        case .customTile2: "Custom Tile 2"
        case .customTile3: "Custom Tile 3"
        case .focusTimer: "Focus Timer"
        case .appearance: "Appearance"
        }
    }

    var subtitle: String {
        switch self {
        case .quickActions: "Open saved apps, folders, web pages, or Shortcuts."
        case .decks: "Choose which modules appear beside the Dock."
        case .notifications: "Choose which local events can alert you."
        case .diagnostics: "Check local tools, permissions, sensors, and connectivity."
        case .terminal: "Control terminal expansion and text."
        case .usage: "Choose how account limits are displayed."
        case .systemStats: "Choose compact local performance metrics."
        case .serviceMonitor: "Check the availability of your services."
        case .weather: "Show current conditions for a selected city."
        case .schedule: "Show the current event or next calendar and reminder item."
        case .clock: "Show local time or another time zone."
        case .music: "Control the macOS Music app."
        case .battery: "Show charge, power state, and time left."
        case .localPorts: "Check local development server TCP ports."
        case .projectPulse: "Show local Git or remote GitHub repository activity."
        case .githubInbox: "Summarize account notifications, reviews, and Actions failures."
        case .docker: "Show local container health and resource use."
        case .customTile, .customTile2, .customTile3: "Show bounded output from a trusted executable or Shortcut."
        case .focusTimer: "Run persistent focus and break countdowns."
        case .appearance: "Adjust the shared panel surface."
        }
    }

    var symbolName: String {
        switch self {
        case .quickActions: "bolt"
        case .decks: "rectangle.stack"
        case .notifications: "bell.badge"
        case .diagnostics: "stethoscope"
        case .terminal: "terminal"
        case .usage: "chart.bar"
        case .systemStats: "gauge.with.dots.needle.67percent"
        case .serviceMonitor: "server.rack"
        case .weather: "cloud.sun"
        case .schedule: "calendar"
        case .clock: "clock"
        case .music: "music.note"
        case .battery: "battery.75percent"
        case .localPorts: "network.badge.shield.half.filled"
        case .projectPulse: "point.3.connected.trianglepath.dotted"
        case .githubInbox: "bell.badge"
        case .docker: "shippingbox"
        case .customTile, .customTile2, .customTile3: "command"
        case .focusTimer: "timer"
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

enum SettingsSidebarSectionID: String {
    case general
    case modules
    case interface
}

struct SettingsSidebarSection: Identifiable, Equatable {
    let id: SettingsSidebarSectionID
    let title: String
    let panes: [SettingsPaneID]
}

enum PanelModuleRegistry {
    static let all = [
        PanelModuleDefinition(
            id: .terminal, title: "Terminal", subtitle: "Interactive login shell",
            symbolName: "terminal", settingsPane: .terminal),
        PanelModuleDefinition(
            id: .usage, title: "Usage", subtitle: "Codex and Claude limits",
            symbolName: "chart.bar", settingsPane: .usage),
        PanelModuleDefinition(
            id: .systemStats, title: "System Stats", subtitle: "Selectable local metrics",
            symbolName: "gauge.with.dots.needle.67percent", settingsPane: .systemStats),
        PanelModuleDefinition(
            id: .serviceMonitor, title: "Service Monitor", subtitle: "HTTPS availability",
            symbolName: "server.rack", settingsPane: .serviceMonitor),
        PanelModuleDefinition(
            id: .weather, title: "Weather", subtitle: "Selected-city conditions",
            symbolName: "cloud.sun", settingsPane: .weather),
        PanelModuleDefinition(
            id: .schedule, title: "Schedule", subtitle: "Calendar and reminders",
            symbolName: "calendar", settingsPane: .schedule),
        PanelModuleDefinition(
            id: .clock, title: "World Clock", subtitle: "Local or selected time zone",
            symbolName: "clock", settingsPane: .clock),
        PanelModuleDefinition(
            id: .music, title: "Music", subtitle: "macOS Music playback",
            symbolName: "music.note", settingsPane: .music),
        PanelModuleDefinition(
            id: .battery, title: "Battery", subtitle: "Charge and power state",
            symbolName: "battery.75percent", settingsPane: .battery),
        PanelModuleDefinition(
            id: .localPorts, title: "Local Ports", subtitle: "Loopback TCP reachability",
            symbolName: "network", settingsPane: .localPorts),
        PanelModuleDefinition(
            id: .projectPulse, title: "Project Pulse", subtitle: "Git and GitHub activity",
            symbolName: "point.3.connected.trianglepath.dotted", settingsPane: .projectPulse),
        PanelModuleDefinition(
            id: .githubInbox, title: "GitHub Inbox", subtitle: "Notifications and reviews",
            symbolName: "bell.badge", settingsPane: .githubInbox),
        PanelModuleDefinition(
            id: .docker, title: "Docker", subtitle: "Containers and resources",
            symbolName: "shippingbox", settingsPane: .docker),
        PanelModuleDefinition(
            id: .customTile, title: "Custom Tile", subtitle: "Command or Shortcut output",
            symbolName: "command", settingsPane: .customTile),
        PanelModuleDefinition(
            id: .customTile2, title: "Custom Tile 2", subtitle: "Command or Shortcut output",
            symbolName: "command", settingsPane: .customTile2),
        PanelModuleDefinition(
            id: .customTile3, title: "Custom Tile 3", subtitle: "Command or Shortcut output",
            symbolName: "command", settingsPane: .customTile3),
        PanelModuleDefinition(
            id: .focusTimer, title: "Focus Timer", subtitle: "Focus and break countdowns",
            symbolName: "timer", settingsPane: .focusTimer),
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
    var claudeRefreshMode: ClaudeUsageRefreshMode
    var fontName: String
    var fontSize: CGFloat
    var displayMode: UsageDisplayMode
    var textColor: UsageTextColor
    var showsPace: Bool
}

struct SystemStatsSettingsState: Equatable {
    var refreshInterval: TimeInterval
    var metrics: [SystemStatsMetric]
    var networkInterfaceName: String = ""
}

struct ServiceMonitorSettingsState: Equatable {
    var endpoints: [ServiceMonitorEndpoint]
    var refreshInterval: TimeInterval
}

struct WeatherSettingsState: Equatable {
    var location: WeatherLocation?
    var temperatureUnit: WeatherTemperatureUnit
    var refreshInterval: TimeInterval
}

struct ScheduleSettingsState: Equatable {
    var calendarIDs: [String]
    var reminderListIDs: [String]
    var includeAllDay: Bool
    var includeReminders: Bool
    var refreshInterval: TimeInterval
}

struct ClockSettingsState: Equatable {
    var timeZoneIdentifier: String
    var hourFormat: ClockHourFormat
    var favorites: [String] = []
}

struct BatterySettingsState: Equatable {
    var refreshInterval: TimeInterval
}

struct AppearanceSettingsState: Equatable {
    var cornerRadius: CGFloat
    var tintOpacity: CGFloat
}

struct SettingsPanelValues: Equatable {
    var deckConfiguration: PanelDeckConfiguration
    var deckAutoSlide: DeckAutoSlideSettings
    var notifications: DockNotificationSettings
    var terminal: TerminalSettingsState
    var usage: UsageSettingsState
    var systemStats: SystemStatsSettingsState
    var serviceMonitor: ServiceMonitorSettingsState
    var weather: WeatherSettingsState
    var schedule: ScheduleSettingsState
    var clock: ClockSettingsState
    var battery: BatterySettingsState
    var projectPulse: ProjectPulseConfiguration
    var githubInbox: GitHubInboxConfiguration
    var docker: DockerConfiguration
    var customTile: CustomTileConfiguration
    var focusTimer: FocusTimerSettings
    var appearance: AppearanceSettingsState
    var extraCustomTiles: [PanelModuleID: CustomTileConfiguration] = [:]
    var localPorts: LocalPortsConfiguration = .init()

    func normalized() -> Self {
        var values = self
        values.deckConfiguration = deckConfiguration.normalized()
        values.deckAutoSlide = deckAutoSlide.normalized()
        values.systemStats.metrics = SystemStatsMetric.normalized(systemStats.metrics)
        values.projectPulse = projectPulse.normalized()
        values.githubInbox = githubInbox.normalized()
        values.docker = docker.normalized()
        values.customTile = customTile.normalized()
        values.extraCustomTiles = extraCustomTiles.filter {
            PanelModuleID.extraCustomTiles.contains($0.key)
        }.mapValues { $0.normalized() }
        values.localPorts = localPorts.normalized()
        values.focusTimer = focusTimer.normalized()
        return values
    }
}

enum TerminalSettingsChange {
    case focusSize(width: CGFloat, height: CGFloat)
    case font(String)
}

enum UsageSettingsChange {
    case providers([UsageProviderID])
    case claudeRefreshMode(ClaudeUsageRefreshMode)
    case displayMode(UsageDisplayMode)
    case font(String)
    case fontSize(CGFloat)
    case textColor(UsageTextColor)
    case showsPace(Bool)
}

enum SystemStatsSettingsChange {
    case refreshInterval(TimeInterval)
    case metrics([SystemStatsMetric])
    case networkInterfaceName(String)
}

enum ServiceMonitorSettingsChange {
    case endpoints([ServiceMonitorEndpoint])
    case refreshInterval(TimeInterval)
}

enum WeatherSettingsChange {
    case location(WeatherLocation?)
    case temperatureUnit(WeatherTemperatureUnit)
    case refreshInterval(TimeInterval)
}

enum ScheduleSettingsChange {
    case calendarIDs([String])
    case reminderListIDs([String])
    case includeAllDay(Bool)
    case includeReminders(Bool)
    case refreshInterval(TimeInterval)
}

enum ClockSettingsChange {
    case favorites([String])
    case timeZoneIdentifier(String)
    case hourFormat(ClockHourFormat)
}

enum BatterySettingsChange {
    case refreshInterval(TimeInterval)
}

enum ProjectPulseSettingsChange {
    case configuration(ProjectPulseConfiguration)
}

enum GitHubInboxSettingsChange {
    case configuration(GitHubInboxConfiguration)
}

enum DockerSettingsChange {
    case configuration(DockerConfiguration)
}

enum FocusTimerSettingsChange {
    case settings(FocusTimerSettings)
}

enum AppearanceSettingsChange {
    case cornerRadius(CGFloat)
    case tintOpacity(CGFloat)
}

enum SettingsPanelChange {
    case deck(PanelDeckConfiguration)
    case deckAutoSlide(DeckAutoSlideSettings)
    case localPorts(LocalPortsConfiguration)
    case notifications(DockNotificationSettings)
    case terminal(TerminalSettingsChange)
    case usage(UsageSettingsChange)
    case systemStats(SystemStatsSettingsChange)
    case serviceMonitor(ServiceMonitorSettingsChange)
    case weather(WeatherSettingsChange)
    case schedule(ScheduleSettingsChange)
    case clock(ClockSettingsChange)
    case battery(BatterySettingsChange)
    case projectPulse(ProjectPulseSettingsChange)
    case githubInbox(GitHubInboxSettingsChange)
    case docker(DockerSettingsChange)
    case customTile(PanelModuleID, CustomTileConfiguration)
    case focusTimer(FocusTimerSettingsChange)
    case appearance(AppearanceSettingsChange)
}
