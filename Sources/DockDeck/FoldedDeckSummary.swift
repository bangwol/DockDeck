import Foundation

struct FoldedDeckSummary: Equatable {
    let value: String
    let detail: String

    static func make(module: PanelModuleID, services: PanelModuleServices, now: Date = Date()) -> Self {
        switch module.current {
        case .terminal:
            return title(.terminal)
        case .usage:
            return usage(services.usage)
        case .systemStats:
            return systemStats(services.systemStats)
        case .serviceMonitor:
            guard let item = services.serviceMonitor.items.first else { return title(.serviceMonitor) }
            return Self(value: item.state.shortLabel,
                        detail: "\(item.endpoint.displayName) · \(item.state.detail)")
        case .weather:
            return weather(services.weather)
        case .clock:
            let identifier = PanelSettings.clockTimeZoneIdentifier
            let zone = ClockTimeZone.resolved(identifier: identifier)
            let format = PanelSettings.clockHourFormat
            return Self(value: ClockTextFormatter.time(now, timeZone: zone, format: format),
                        detail: "\(ClockTextFormatter.date(now, timeZone: zone)) · \(zone.identifier)")
        case .music:
            guard services.music.status == .ready, let snapshot = services.music.snapshot else { return title(.music) }
            let state = snapshot.state
            let value = state.isPlaying ? "PLAY" : state == .paused ? "PAUSE" : "STOP"
            let detail = snapshot.track.map { "\($0.title) · \($0.artist) · \(state.title)" } ?? state.title
            return Self(value: value, detail: detail)
        case .battery:
            guard let snapshot = services.battery.snapshot,
                snapshot.percent.isFinite
            else { return Self(value: "--", detail: L10n.text("No internal battery")) }
            return Self(value: "\(Int(snapshot.percent.rounded()))%", detail: snapshot.state.title)
        case .focusTimer:
            let snapshot = services.focusTimer.snapshot
            return Self(value: snapshot.timeLabel,
                        detail: "\(snapshot.phase.title) · \(snapshot.mode.rawValue)")
        case .projectPulse:
            guard let snapshot = services.projectPulse.snapshot,
                services.projectPulse.status == .ready
            else { return title(.projectPulse, detail: projectStatus(services.projectPulse.status)) }
            let git = snapshot.git
            let value = git.conflictCount > 0 ? "!\(git.conflictCount)"
                : git.changeCount == 0 ? "CLEAN" : "Δ\(git.changeCount)"
            return Self(value: value,
                        detail: "\(git.repositoryName) · \(git.branch) · \(git.changeCount) changes · ahead \(git.aheadCount), behind \(git.behindCount)")
        case .githubInbox:
            guard let snapshot = services.githubInbox.snapshot,
                services.githubInbox.status == .ready
            else { return title(.githubInbox, detail: githubStatus(services.githubInbox.status)) }
            return Self(value: String(snapshot.unreadCount),
                        detail: "\(snapshot.unreadCount) unread · \(snapshot.mentionCount) mentions · \(snapshot.reviewRequestCount) reviews")
        case .docker:
            guard let snapshot = services.docker.snapshot,
                services.docker.status == .ready
            else { return title(.docker, detail: dockerStatus(services.docker.status)) }
            return Self(value: String(snapshot.runningCount),
                        detail: "\(snapshot.runningCount) running · \(snapshot.stoppedCount) stopped · \(snapshot.unhealthyCount) unhealthy")
        case .customTile, .customTile2, .customTile3:
            guard let store = services.runtime(for: module) as? CustomTileStore else { return title(module) }
            guard store.status == .ready, let snapshot = store.snapshot else {
                return title(module, detail: store.accessibilitySummary)
            }
            return Self(value: compactTileValue(snapshot.content.value),
                        detail: store.accessibilitySummary)
        default:
            return title(module)
        }
    }

    static func usagePercent(_ value: Double?, freshness: UsageFreshness) -> String {
        guard freshness == .live, let value, value.isFinite else { return "--" }
        return "\(Int(min(max(value, 0), 100).rounded()))%"
    }

    private static func usage(_ store: UsageStore) -> Self {
        guard let provider = store.providers.first else { return title(.usage) }
        guard let window = provider.windows.first else {
            let state = [provider.freshness.label, provider.detail].compactMap { $0 }.joined(separator: " · ")
            return Self(value: "--", detail: "\(provider.name) · \(state.isEmpty ? L10n.text("Usage unavailable") : state)")
        }
        let mode = PanelSettings.usageDisplayMode
        let value = usagePercent(mode.value(for: window), freshness: provider.freshness)
        let windowName = window.customLabel == "FBL" ? "Fable weekly limit" : window.label
        let state = provider.freshness.label.map { " · \($0)" } ?? ""
        let failure = provider.detail.map { " · \($0)" } ?? ""
        return Self(value: value, detail: "\(provider.name) · \(windowName) · \(mode.title.lowercased()) · \(UsageResetFormatter.helpText(for: window))\(state)\(failure)")
    }

    private static func systemStats(_ store: SystemStatsStore) -> Self {
        guard let metric = store.selectedMetrics.first else { return title(.systemStats) }
        let snapshot = store.snapshot
        let value: String
        let context: String
        switch metric {
        case .cpu: value = percent(snapshot.cpuPercent); context = "used"
        case .gpu: value = percent(snapshot.gpuPercent); context = "used"
        case .memory: value = percent(snapshot.memoryPercent); context = "used"
        case .disk: value = percent(snapshot.diskPercent); context = "used"
        case .network:
            value = ByteRateFormatter.compactString(snapshot.downloadBytesPerSecond)
            context = "download bytes/s"
        case .thermal:
            value = snapshot.temperatureCelsius.map { $0.isFinite ? "\(Int($0.rounded()))°C" : "--" } ?? "--"
            context = snapshot.thermalPressure?.accessibilityTitle ?? "thermal state unavailable"
        }
        return Self(value: value, detail: "\(L10n.text(metric.title)) · \(value == "--" ? L10n.text("Unavailable") : "\(value) \(context)")")
    }

    private static func weather(_ store: WeatherStore) -> Self {
        guard let snapshot = store.snapshot else {
            let detail = switch store.status {
            case .idle: L10n.text("Choose a city in Settings")
            case .loading: L10n.text("Loading weather")
            case .ready: L10n.text("Weather unavailable")
            case .failed(let reason): reason
            }
            return Self(value: "--", detail: detail)
        }
        let temperature = shortTemperature(snapshot.temperature, unit: snapshot.temperatureUnit)
        let condition = WeatherCondition.title(code: snapshot.weatherCode)
        switch store.status {
        case .ready:
            return Self(value: temperature, detail: "\(snapshot.location.name) · \(condition) · feels like \(shortTemperature(snapshot.apparentTemperature, unit: snapshot.temperatureUnit))")
        case .failed(let reason):
            return Self(value: "--", detail: "\(snapshot.location.name) · last known \(temperature) · \(reason)")
        case .loading:
            return Self(value: "--", detail: "\(snapshot.location.name) · \(L10n.text("Loading weather"))")
        case .idle:
            return Self(value: "--", detail: L10n.text("Choose a city in Settings"))
        }
    }

    private static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(min(max(value, 0), 100).rounded()))%"
    }

    private static func projectStatus(_ status: ProjectPulseStatus) -> String {
        switch status {
        case .notConfigured: L10n.text("Choose a repository")
        case .loading: L10n.text("Reading repository…")
        case .ready: L10n.text("Repository unavailable")
        case .failed(let message): message
        }
    }

    private static func githubStatus(_ status: GitHubInboxStatus) -> String {
        switch status {
        case .loading: L10n.text("Loading GitHub Inbox")
        case .ready: L10n.text("GitHub Inbox unavailable")
        case .unavailable(let message): message
        }
    }

    private static func dockerStatus(_ status: DockerStatus) -> String {
        switch status {
        case .loading: L10n.text("Loading Docker")
        case .ready: L10n.text("Docker unavailable")
        case .unavailable(let message): message
        }
    }

    private static func compactTileValue(_ value: String) -> String {
        value.count <= 5 ? value : "\(value.prefix(4))…"
    }

    private static func shortTemperature(_ value: Double, unit: WeatherTemperatureUnit) -> String {
        guard value.isFinite else { return "--" }
        return "\(Int(value.rounded()))\(unit.symbol)"
    }

    private static func title(_ module: PanelModuleID, detail: String? = nil) -> Self {
        let title = L10n.text(PanelModuleRegistry.definition(for: module)?.title ?? module.rawValue)
        return Self(value: title, detail: detail ?? title)
    }
}
