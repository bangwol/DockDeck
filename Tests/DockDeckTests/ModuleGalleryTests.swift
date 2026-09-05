import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class ModuleGalleryTests: XCTestCase {
    func testRenderModuleGallery() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "DOCKDECK_UI_GALLERY_DIR"],
            !outputPath.isEmpty
        else {
            throw XCTSkip("Set DOCKDECK_UI_GALLERY_DIR to render the gallery")
        }
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputURL, withIntermediateDirectories: true)
        let services = makeServices()

        for (themeName, theme) in [
            ("dark", Theme.theme(id: "")),
            ("light", Theme.theme(id: "github-light")),
        ] {
            for module in PanelModuleID.readOnlyBuiltIns {
                try render(ReadOnlyDeckPanelView(readabilityOverride: true, services: services,
                    presentation: ReadOnlyDeckPresentation(activeModule: module, theme: theme)),
                    size: NSSize(width: 214, height: 59), dark: theme.isDark,
                    to: outputURL.appendingPathComponent("\(themeName)-readable-\(module.rawValue).png"))
            }
            for module in PanelModuleID.readOnlyBuiltIns {
                let presentation = ReadOnlyDeckPresentation(
                    activeModule: module, theme: theme)
                try render(
                    ReadOnlyDeckPanelView(
                        services: services, presentation: presentation),
                    size: NSSize(width: 214, height: 59),
                    dark: theme.isDark,
                    to: outputURL.appendingPathComponent(
                        "\(themeName)-compact-\(module.rawValue).png"))
            }
            for module in PanelModuleID.readOnlyBuiltIns {
                let presentation = ReadOnlyDeckPresentation(
                    activeModule: module, theme: theme)
                try render(
                    ReadOnlyModuleDetailView(
                        services: services, presentation: presentation),
                    size: ReadOnlyModuleDetailLayout.initialSize,
                    dark: theme.isDark,
                    to: outputURL.appendingPathComponent(
                        "\(themeName)-detail-\(module.rawValue).png"))
                if module == .clock {
                    try render(ClockModuleDetailView(store: services.clock,
                        timeZoneIdentifier: "Asia/Seoul", hourFormat: .twentyFourHour,
                        favorites: ["Asia/Seoul", "America/Los_Angeles", "Europe/London"])
                        .background(Color(nsColor: .windowBackgroundColor)),
                        size: NSSize(width: 528, height: 250), dark: theme.isDark,
                        to: outputURL.appendingPathComponent("\(themeName)-clock-favorites.png"))
                }
                if module == .battery {
                    try render(ReadOnlyModuleDetailView(services: services, presentation: presentation),
                        size: ReadOnlyModuleDetailLayout.minimumSize, dark: theme.isDark,
                        to: outputURL.appendingPathComponent("\(themeName)-detail-battery-minimum.png"))
                }
            }
        }
    }

    private func render<V: View>(
        _ rootView: V, size: NSSize, dark: Bool, to url: URL
    ) throws {
        let view = NSHostingView(
            rootView: rootView.frame(width: size.width, height: size.height))
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
    }

    private func makeServices() -> PanelModuleServices {
        let now = Date(timeIntervalSince1970: 1_788_497_400)
        let location = WeatherLocation(
            id: 1, name: "Seoul", latitude: 37.5665, longitude: 126.978,
            countryCode: "KR", country: "South Korea", admin1: "Seoul",
            timezone: "Asia/Seoul")
        let usage = UsageStore(initialProviders: [
            ProviderUsage(
                id: .codex, name: "CODEX",
                windows: [
                    UsageWindow(
                        durationMinutes: 7 * 24 * 60, usedPercent: 18,
                        resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60)),
                ],
                freshness: .live, detail: "pro"),
            ProviderUsage(
                id: .claude, name: "CLAUDE",
                windows: [
                    UsageWindow(
                        durationMinutes: 5 * 60, usedPercent: 32,
                        resetsAt: now.addingTimeInterval(2 * 60 * 60)),
                    UsageWindow(
                        durationMinutes: 7 * 24 * 60, usedPercent: 46,
                        resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60)),
                    UsageWindow(
                        durationMinutes: 7 * 24 * 60, usedPercent: 21,
                        resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60),
                        customLabel: "FBL"),
                ],
                freshness: .live, detail: nil),
        ])
        let stats = SystemStatsStore(
            metrics: [.cpu, .memory, .network, .thermal],
            initialSnapshot: SystemStatsSnapshot(
                cpuPercent: 18, memoryPercent: 72,
                downloadBytesPerSecond: 2_400_000,
                uploadBytesPerSecond: 360_000,
                temperatureCelsius: 54, thermalPressure: .nominal))
        let service = ServiceMonitorStore(endpoints: [
            ServiceMonitorEndpoint(name: "API", urlString: "https://example.com"),
            ServiceMonitorEndpoint(name: "Web", urlString: "https://example.org"),
        ])
        let weatherHours: [WeatherHour] = (0..<12).map { index in
            let date = now.addingTimeInterval(Double(index) * 3_600)
            let temperature = 24.0 + Double(index % 4)
            return WeatherHour(date: date, temperature: temperature,
                precipitationProbability: index * 7, weatherCode: index < 4 ? 0 : 63,
                isDay: index < 6)
        }
        let weather = WeatherStore(
            location: location,
            initialSnapshot: WeatherSnapshot(
                location: location, temperature: 24, apparentTemperature: 25,
                highTemperature: 27, lowTemperature: 19, weatherCode: 2,
                isDay: true, temperatureUnit: .celsius, receivedAt: now,
                hourly: weatherHours))
        let schedule = ScheduleStore(
            includeReminders: true,
            provider: GalleryScheduleProvider(now: Date()))
        schedule.start()
        let projectSnapshot = ProjectPulseSnapshot(
            git: ProjectGitSnapshot(
                repositoryName: "DockDeck", branch: "main", stagedCount: 0,
                modifiedCount: 2, untrackedCount: 1, conflictCount: 0,
                aheadCount: 1, behindCount: 0),
            github: ProjectGitHubSnapshot(
                nameWithOwner: "example/DockDeck", defaultBranch: "main",
                headOID: "abc1234", commitsLastSevenDays: 14,
                openPullRequests: 2, openIssues: 5, stargazerCount: 128,
                forkCount: 9, isPrivate: false, pushedAt: now),
            workflow: ProjectWorkflowSnapshot(state: .success, title: "Build passing"))
        let inboxSnapshot = GitHubInboxSnapshot(
            unreadCount: 6, mentionCount: 2, reviewRequestCount: 1,
            ciNotificationCount: 1, failedRunsLastSevenDays: 1,
            actionsRepository: "example/DockDeck",
            entries: [
                GitHubInboxEntry(
                    id: "1", title: "Improve compact layout",
                    repository: "example/DockDeck", reason: "review_requested",
                    updatedAt: now,
                    webURL: URL(string: "https://github.com/example/DockDeck/pull/12")),
                GitHubInboxEntry(
                    id: "2", title: "Fix refresh scheduling",
                    repository: "example/DockDeck", reason: "mention",
                    updatedAt: now.addingTimeInterval(-900),
                    webURL: URL(string: "https://github.com/example/DockDeck/issues/18")),
            ],
            observedAt: now)
        var networkSample: UInt64 = 0
        let network = NetworkStore(
            initialConnection: NetworkConnectionSnapshot(
                status: .online, kind: .wifi, isExpensive: false, isConstrained: false),
            interfaceName: "en0", counterReader: { _ in
                networkSample += 1
                return NetworkCounters(interfaceName: "en0",
                    receivedBytes: networkSample * networkSample * 600_000,
                    sentBytes: networkSample * networkSample * 90_000)
            })
        for offset in [-2.0, -1.0, 0.0] { network.refresh(now: now.addingTimeInterval(offset)) }
        return PanelModuleServices(
            usage: usage,
            systemStats: stats,
            serviceMonitor: service,
            weather: weather,
            schedule: schedule,
            clock: ClockStore(now: now),
            music: MusicStore(
                initialSnapshot: MusicPlaybackSnapshot(
                    state: .playing,
                    track: MusicTrackSnapshot(
                        title: "Midnight Drive", artist: "DockDeck",
                        album: "Preview", duration: 240, position: 90),
                    observedAt: Date()),
                initialStatus: .ready),
            battery: BatteryStore(
                initialSnapshot: BatterySnapshot(
                    percent: 76, state: .discharging, minutesRemaining: 310)),
            network: network,
            localPorts: LocalPortsStore(initialItems: [
                .init(port: 3000, state: .open), .init(port: 5173, state: .closed),
                .init(port: 8080, state: .unavailable("Permission denied while checking the local port.")),
                .init(port: 5432, state: .closed), .init(port: 65535, state: .open),
            ]),
            projectPulse: ProjectPulseStore(
                configuration: ProjectPulseConfiguration(
                    source: .github, githubRepository: "example/DockDeck"),
                initialSnapshot: projectSnapshot),
            githubInbox: GitHubInboxStore(initialSnapshot: inboxSnapshot),
            docker: DockerStore(
                initialSnapshot: DockerSnapshot(
                    runningCount: 3, stoppedCount: 1, unhealthyCount: 0,
                    cpuPercent: 4.2, memoryBytes: 640 * 1_048_576,
                    observedAt: now, containers: [
                        DockerContainerMetric(id: "worker", name: "build-worker", cpuPercent: 3.8, memoryBytes: 512 * 1_048_576),
                        DockerContainerMetric(id: "api", name: "development-api-with-a-long-container-name", cpuPercent: 0.3, memoryBytes: 96 * 1_048_576),
                        DockerContainerMetric(id: "db", name: "database", cpuPercent: 0.1, memoryBytes: 32 * 1_048_576),
                    ])),
            customTile: CustomTileStore(
                initialSnapshot: CustomTileSnapshot(
                    content: CustomTileContent(
                        title: "Build", value: "Passing", detail: "main",
                        symbolName: "checkmark.seal.fill"),
                    observedAt: now)),
            focusTimer: FocusTimerStore(now: now))
    }
}

private final class GalleryScheduleProvider: ScheduleEventProviding {
    let authorizationState = ScheduleAuthorizationState.granted
    let reminderAuthorizationState = ScheduleAuthorizationState.granted
    var onStoreChanged: (() -> Void)?
    private let now: Date

    init(now: Date) {
        self.now = now
    }

    func requestAccess(completion: @escaping (ScheduleAuthorizationState) -> Void) {
        completion(.granted)
    }

    func requestReminderAccess(
        completion: @escaping (ScheduleAuthorizationState) -> Void
    ) {
        completion(.granted)
    }

    func suspend() {}

    func fetch(
        from startDate: Date,
        to endDate: Date,
        reminderStartDate: Date,
        selectedCalendarIDs: Set<String>,
        selectedReminderListIDs: Set<String>,
        includeAllDay: Bool,
        includeReminders: Bool,
        completion: @escaping (ScheduleFetchResult) -> Void
    ) {
        completion(ScheduleFetchResult(
            calendars: [ScheduleCalendarSource(id: "work", title: "Work")],
            events: [
                ScheduleEventItem(
                    id: "event", title: "Design review",
                    startDate: now.addingTimeInterval(-900),
                    endDate: now.addingTimeInterval(2_700), isAllDay: false,
                    calendarTitle: "Work"),
            ],
            reminderLists: [
                ScheduleReminderListSource(id: "tasks", title: "Tasks"),
            ],
            reminders: [
                ScheduleReminderItem(
                    id: "reminder", title: "Publish preview notes",
                    dueDate: now.addingTimeInterval(7_200), isAllDay: false,
                    listTitle: "Tasks"),
            ]))
    }
}
