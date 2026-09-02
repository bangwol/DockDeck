import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class PanelAppearanceTests: XCTestCase {
    func testEnabledPanelsKeepsSingleSelectionsAndRecoversEmptyState() {
        XCTAssertEqual(EnabledPanels.resolved(.terminal), .terminal)
        XCTAssertEqual(EnabledPanels.resolved(.usage), .usage)
        XCTAssertEqual(EnabledPanels.resolved([]), .all)
    }

    func testDeckConfigurationAdaptsExistingPlacementAndVisibility() {
        let configuration = PanelDeckConfiguration.legacy(
            order: .terminalRight, enabledPanels: .terminal)

        XCTAssertEqual(
            configuration.left,
            [
                .usage, .systemStats, .serviceMonitor, .weather, .schedule, .clock, .battery,
                .network,
            ])
        XCTAssertEqual(configuration.right, [.terminal])
        XCTAssertEqual(configuration.enabled, [.terminal])
        XCTAssertEqual(configuration.side(containing: .terminal), .right)
    }

    func testDeckConfigurationKeepsFutureModulesWhileRemovingDuplicates() throws {
        let futureModule = PanelModuleID(rawValue: "future-clock")
        let configuration = PanelDeckConfiguration(
            left: [.terminal, futureModule, .terminal],
            right: [.usage, futureModule],
            enabled: [futureModule, futureModule]
        ).normalized()
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(PanelDeckConfiguration.self, from: data)

        XCTAssertEqual(decoded.left, [futureModule, .terminal])
        XCTAssertEqual(
            decoded.right,
            [
                .usage, .systemStats, .serviceMonitor, .weather, .schedule, .clock, .battery,
                .network,
            ])
        XCTAssertEqual(decoded.enabled, [futureModule])
    }

    func testDeckConfigurationPreservesPerModuleSideAssignments() {
        let configuration = PanelDeckConfiguration(
            left: [.terminal, .systemStats],
            right: [.usage],
            enabled: [.terminal, .usage, .systemStats]
        ).normalized()

        XCTAssertEqual(configuration.left, [.terminal, .systemStats])
        XCTAssertEqual(
            configuration.right,
            [
                .usage, .serviceMonitor, .weather, .schedule, .clock, .battery, .network,
            ])
    }

    func testDeckConfigurationKeepsEnabledModulesAboveDisabledModules() {
        let configuration = PanelDeckConfiguration(
            left: [.terminal, .weather, .systemStats],
            right: [.usage],
            enabled: [.usage, .systemStats]
        ).normalized()

        XCTAssertEqual(configuration.left, [.systemStats, .terminal, .weather])
        XCTAssertEqual(configuration.right.first, .usage)
    }

    func testDeckConfigurationAllowsEveryModuleOnOneSide() {
        let allLeft = PanelDeckConfiguration(
            left: PanelModuleID.builtIns,
            right: [],
            enabled: [.terminal, .usage]
        ).normalized()
        let allRight = PanelDeckConfiguration(
            left: [],
            right: PanelModuleID.builtIns,
            enabled: [.terminal, .usage]
        ).normalized()

        XCTAssertEqual(allLeft.left, PanelModuleID.builtIns)
        XCTAssertTrue(allLeft.right.isEmpty)
        XCTAssertTrue(allLeft.enabledModules(on: .right).isEmpty)
        XCTAssertTrue(allRight.left.isEmpty)
        XCTAssertEqual(allRight.right, PanelModuleID.builtIns)
        XCTAssertTrue(allRight.enabledModules(on: .left).isEmpty)
    }

    func testSettingsModelSwapsCompleteDecksWithoutDroppingFutureModules() {
        let futureModule = PanelModuleID(rawValue: "future-clock")
        let model = makeSettingsModel(
            configuration: PanelDeckConfiguration(
                left: [.terminal, futureModule], right: [.usage],
                enabled: [.terminal, .usage, futureModule]))
        var persistedConfiguration: PanelDeckConfiguration?
        model.onChange = {
            if case .deck(let configuration) = $0 {
                persistedConfiguration = configuration
            }
        }

        model.swapDecks()

        XCTAssertEqual(
            model.values.deckConfiguration.left,
            [
                .usage, .systemStats, .serviceMonitor, .weather, .schedule, .clock, .battery,
                .network,
            ])
        XCTAssertEqual(model.values.deckConfiguration.right, [.terminal, futureModule])
        XCTAssertEqual(persistedConfiguration, model.values.deckConfiguration)
    }

    func testSettingsModelMovesModulesAcrossDecksAndMaintainsStatusGroups() {
        let model = makeSettingsModel(
            configuration: PanelDeckConfiguration(
                left: [.terminal], right: [.usage, .systemStats],
                enabled: [.terminal, .usage, .systemStats]))
        var persistedConfiguration: PanelDeckConfiguration?
        model.onChange = {
            if case .deck(let configuration) = $0 { persistedConfiguration = configuration }
        }

        model.moveModule(.systemStats, to: .left, before: .terminal)

        XCTAssertEqual(model.values.deckConfiguration.left, [.systemStats, .terminal])
        XCTAssertEqual(model.side(containing: .systemStats), .left)
        XCTAssertEqual(persistedConfiguration, model.values.deckConfiguration)

        model.setEnabled(false, for: .systemStats)

        XCTAssertEqual(model.values.deckConfiguration.left, [.terminal, .systemStats])
        XCTAssertEqual(Array(model.moduleDefinitions.prefix(2).map(\.id)), [.terminal, .usage])
        XCTAssertTrue(model.moduleDefinitions.dropFirst(2).allSatisfy { !model.isEnabled($0.id) })
    }

    func testSettingsModelCanEmptyADeck() {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))

        for module in model.moduleDefinitions(on: .right).map(\.id) {
            model.moveModule(module, to: .left)
        }

        XCTAssertEqual(
            model.moduleDefinitions(on: .left).map(\.id),
            PanelModuleID.builtIns)
        XCTAssertTrue(model.moduleDefinitions(on: .right).isEmpty)
    }

    func testDeckDragPayloadUsesPlainTextAndRejectsExternalText() {
        let provider = DeckModuleDragPayload.itemProvider(for: .weather)

        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(
                DeckModuleDragPayload.contentType.identifier))
        XCTAssertEqual(
            DeckModuleDragPayload.moduleID(from: "dockdeck-module:weather"),
            .weather)
        XCTAssertNil(DeckModuleDragPayload.moduleID(from: "weather"))
        XCTAssertNil(DeckModuleDragPayload.moduleID(from: "dockdeck-module:unknown"))
    }

    func testSettingsModelKeepsTheLastModuleVisible() {
        let unavailableModule = PanelModuleID(rawValue: "future-module")
        let model = makeSettingsModel(
            configuration: PanelDeckConfiguration(
                left: [.terminal], right: [.usage, unavailableModule],
                enabled: [.terminal, unavailableModule]))
        var callbackCount = 0
        model.onChange = { _ in callbackCount += 1 }

        model.setEnabled(false, for: .terminal)

        XCTAssertTrue(model.isEnabled(.terminal))
        XCTAssertEqual(callbackCount, 0)
    }

    func testModuleRegistryBuildsSettingsSidebarWithoutDuplicateIDs() {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))

        XCTAssertEqual(Set(PanelModuleRegistry.all.map(\.id)).count, PanelModuleRegistry.all.count)
        XCTAssertEqual(
            model.availablePanes,
            [
                .decks, .terminal, .usage, .systemStats, .serviceMonitor, .weather, .schedule,
                .clock, .battery, .network, .appearance,
            ])
        XCTAssertEqual(model.moduleDefinition(for: .usage)?.id, .usage)
        XCTAssertEqual(model.moduleDefinition(for: .systemStats)?.id, .systemStats)
        XCTAssertEqual(model.moduleDefinition(for: .serviceMonitor)?.id, .serviceMonitor)
        XCTAssertEqual(model.moduleDefinition(for: .weather)?.id, .weather)
        XCTAssertEqual(model.moduleDefinition(for: .schedule)?.id, .schedule)
        XCTAssertEqual(model.moduleDefinition(for: .clock)?.id, .clock)
        XCTAssertEqual(model.moduleDefinition(for: .battery)?.id, .battery)
        XCTAssertEqual(model.moduleDefinition(for: .network)?.id, .network)
    }

    func testModuleRuntimeCoordinatorStartsAndStopsOnlyChangedModules() {
        let coordinator = ModuleRuntimeCoordinator()
        var terminalStarts = 0
        var terminalStops = 0
        var usageStarts = 0
        var usageStops = 0
        coordinator.register(
            .terminal, start: { terminalStarts += 1 }, stop: { terminalStops += 1 })
        coordinator.register(
            .usage, start: { usageStarts += 1 }, stop: { usageStops += 1 })

        coordinator.synchronize(enabledModules: [.terminal])
        coordinator.synchronize(enabledModules: [.terminal])
        coordinator.synchronize(enabledModules: [.usage, PanelModuleID(rawValue: "future")])
        coordinator.stopAll()

        XCTAssertEqual(terminalStarts, 1)
        XCTAssertEqual(terminalStops, 1)
        XCTAssertEqual(usageStarts, 1)
        XCTAssertEqual(usageStops, 1)
    }

    func testUsageSettingsKeepsOneProviderEnabled() {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))

        model.setUsageProvider(.claude, enabled: false)
        model.setUsageProvider(.codex, enabled: false)

        XCTAssertEqual(model.values.usage.enabledProviders, [.codex])
    }

    func testSettingsModelEmitsModuleScopedChanges() {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))
        var emittedSize: CGFloat?
        model.onChange = {
            if case .usage(.fontSize(let size)) = $0 { emittedSize = size }
        }

        model.setUsageFontSize(12.4)

        XCTAssertEqual(model.values.usage.fontSize, 12)
        XCTAssertEqual(emittedSize, 12)
    }

    func testSettingsModelRoundsSystemStatsRefreshInterval() {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))
        var emittedInterval: TimeInterval?
        model.onChange = {
            if case .systemStats(.refreshInterval(let interval)) = $0 {
                emittedInterval = interval
            }
        }

        model.setSystemStatsRefreshInterval(4.2)

        XCTAssertEqual(model.values.systemStats.refreshInterval, 5)
        XCTAssertEqual(emittedInterval, 5)
    }

    func testSettingsModelKeepsTwoToFourSystemStatsMetrics() {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))
        var emittedMetrics: [SystemStatsMetric]?
        model.onChange = {
            if case .systemStats(.metrics(let metrics)) = $0 { emittedMetrics = metrics }
        }

        model.setSystemStatsMetric(.thermal, enabled: true)
        XCTAssertEqual(model.values.systemStats.metrics, SystemStatsMetric.defaultSelection)

        model.setSystemStatsMetric(.disk, enabled: false)
        model.setSystemStatsMetric(.thermal, enabled: true)
        XCTAssertEqual(model.values.systemStats.metrics, [.cpu, .memory, .network, .thermal])
        XCTAssertEqual(emittedMetrics, [.cpu, .memory, .network, .thermal])

        model.setSystemStatsMetric(.network, enabled: false)
        model.setSystemStatsMetric(.thermal, enabled: false)
        XCTAssertEqual(model.values.systemStats.metrics, [.cpu, .memory])
    }

    func testSettingsModelEmitsNormalizedWeatherChanges() {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))
        let location = WeatherLocation(
            id: 1_835_848, name: " Seoul ", latitude: 37.566, longitude: 126.9784,
            countryCode: "kr", country: "South Korea", admin1: "Seoul",
            timezone: "Asia/Seoul")
        var changes: [SettingsPanelChange] = []
        model.onChange = { changes.append($0) }

        model.setWeatherLocation(location)
        model.setWeatherTemperatureUnit(.fahrenheit)
        model.setWeatherRefreshInterval(1_000)

        XCTAssertEqual(model.values.weather.location?.name, "Seoul")
        XCTAssertEqual(model.values.weather.location?.countryCode, "KR")
        XCTAssertEqual(model.values.weather.temperatureUnit, .fahrenheit)
        XCTAssertEqual(model.values.weather.refreshInterval, 900)
        XCTAssertEqual(changes.count, 3)
    }

    func testReadOnlyDeckSelectionCyclesEnabledModules() {
        let modules: [PanelModuleID] = [.usage, .systemStats]

        XCTAssertEqual(
            ReadOnlyDeckSelection.resolved(preferred: .systemStats, enabledModules: modules),
            .systemStats)
        XCTAssertEqual(
            ReadOnlyDeckSelection.resolved(
                preferred: PanelModuleID(rawValue: "missing"), enabledModules: modules),
            .usage)
        XCTAssertEqual(
            ReadOnlyDeckSelection.next(after: .usage, enabledModules: modules), .systemStats)
        XCTAssertEqual(
            ReadOnlyDeckSelection.next(after: .systemStats, enabledModules: modules), .usage)
        XCTAssertEqual(
            ReadOnlyDeckSelection.previous(before: .usage, enabledModules: modules),
            .systemStats)
        XCTAssertEqual(
            ReadOnlyDeckSelection.previous(before: .systemStats, enabledModules: modules),
            .usage)
    }

    func testDeckScrollDirectionUsesVerticalAxis() {
        XCTAssertEqual(
            DeckScrollDirection.resolved(deltaX: 0, deltaY: 1), .previous)
        XCTAssertEqual(
            DeckScrollDirection.resolved(deltaX: 0, deltaY: -1), .next)
        XCTAssertNil(DeckScrollDirection.resolved(deltaX: 2, deltaY: 1))
        XCTAssertNil(DeckScrollDirection.resolved(deltaX: 0, deltaY: 0))
    }

    func testDeckSelectionsAreIndependentBySide() {
        let previousConfiguration = PanelSettings.deckConfiguration
        let previousLeft = PanelSettings.activeModule(on: .left)
        let previousRight = PanelSettings.activeModule(on: .right)
        defer {
            PanelSettings.deckConfiguration = previousConfiguration
            PanelSettings.setActiveModule(previousLeft, on: .left)
            PanelSettings.setActiveModule(previousRight, on: .right)
        }
        PanelSettings.deckConfiguration = PanelDeckConfiguration(
            left: [.terminal, .systemStats], right: [.usage, .weather],
            enabled: [.terminal, .systemStats, .usage, .weather])

        PanelSettings.setActiveModule(.systemStats, on: .left)
        PanelSettings.setActiveModule(.weather, on: .right)

        XCTAssertEqual(PanelSettings.activeModule(on: .left), .systemStats)
        XCTAssertEqual(PanelSettings.activeModule(on: .right), .weather)
    }

    func testEmptyDeckHasNoActiveModule() {
        let previousConfiguration = PanelSettings.deckConfiguration
        let previousLeft = PanelSettings.activeModule(on: .left)
        let previousRight = PanelSettings.activeModule(on: .right)
        defer {
            PanelSettings.deckConfiguration = previousConfiguration
            PanelSettings.setActiveModule(previousLeft, on: .left)
            PanelSettings.setActiveModule(previousRight, on: .right)
        }
        PanelSettings.deckConfiguration = PanelDeckConfiguration(
            left: PanelModuleID.builtIns,
            right: [],
            enabled: [.terminal, .usage])

        XCTAssertNil(PanelSettings.activeModule(on: .right))
    }

    func testSettingsModelLimitsServiceMonitorEndpoints() {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))

        for _ in 0...ServiceMonitorEndpoint.maximumCount {
            model.addServiceMonitorEndpoint()
        }

        XCTAssertEqual(
            model.values.serviceMonitor.endpoints.count,
            ServiceMonitorEndpoint.maximumCount)
    }

    func testSettingsPanesRenderAtPreferredSize() throws {
        let enabled = PanelDeckConfiguration.legacy(
            order: .terminalLeft, enabledPanels: .all)
        var usageDisabled = enabled
        usageDisabled.setEnabled(false, for: .usage)
        let scenarios = SettingsPaneID.allCases.map { ($0, enabled) }
            + [(.usage, usageDisabled)]

        for (pane, configuration) in scenarios {
            let view = SettingsPanelView(
                selectedPane: pane,
                values: makeSettingsValues(configuration: configuration),
                fontNames: ["Menlo", TerminalTheme.systemFontName])
            view.frame = NSRect(origin: .zero, size: SettingsPanelView.preferredSize)
            view.layoutSubtreeIfNeeded()

            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)

            XCTAssertEqual(view.frame.size, SettingsPanelView.preferredSize)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        }
    }

    func testEmptyDeckDropZoneRenders() throws {
        let configuration = PanelDeckConfiguration(
            left: [],
            right: PanelModuleID.builtIns,
            enabled: [.terminal, .usage]
        ).normalized()
        let model = makeSettingsModel(configuration: configuration)
        let snapshotSize = NSSize(width: 620, height: 640)
        let rootView = DecksSettingsView(model: model)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let view = NSHostingView(rootView: rootView)
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(origin: .zero, size: snapshotSize)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, snapshotSize)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    func testServiceSettingsRenderMaximumEndpoints() throws {
        var configuration = PanelDeckConfiguration.legacy(
            order: .terminalLeft, enabledPanels: .all)
        configuration.setEnabled(true, for: .serviceMonitor)
        var values = makeSettingsValues(configuration: configuration)
        values.serviceMonitor.endpoints = (1...ServiceMonitorEndpoint.maximumCount).map {
            ServiceMonitorEndpoint(
                name: "Service \($0)",
                urlString: "https://service\($0).example.com/health")
        }
        let view = SettingsPanelView(
            selectedPane: .serviceMonitor,
            values: values,
            fontNames: ["Menlo", TerminalTheme.systemFontName])
        view.frame = NSRect(origin: .zero, size: SettingsPanelView.preferredSize)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertEqual(view.frame.size, SettingsPanelView.preferredSize)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    func testWeatherSettingsRenderSelectedLocation() throws {
        var configuration = PanelDeckConfiguration.legacy(
            order: .terminalLeft, enabledPanels: .all)
        configuration.setEnabled(true, for: .weather)
        var values = makeSettingsValues(configuration: configuration)
        values.weather.location = WeatherLocation(
            id: 1_835_848, name: "Seoul", latitude: 37.566, longitude: 126.9784,
            countryCode: "KR", country: "South Korea", admin1: "Seoul",
            timezone: "Asia/Seoul")
        let view = SettingsPanelView(
            selectedPane: .weather,
            values: values,
            fontNames: ["Menlo", TerminalTheme.systemFontName])
        view.frame = NSRect(origin: .zero, size: SettingsPanelView.preferredSize)
        view.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertEqual(view.frame.size, SettingsPanelView.preferredSize)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    func testShellRestartPolicyStopsARepeatedExitLoop() {
        var policy = ShellRestartPolicy()
        let start = Date(timeIntervalSince1970: 100)

        policy.recordStart(at: start)
        XCTAssertTrue(policy.shouldRestart(afterExitAt: start.addingTimeInterval(3)))
        for offset in 4...5 {
            let nextStart = start.addingTimeInterval(TimeInterval(offset))
            policy.recordStart(at: nextStart)
            XCTAssertTrue(
                policy.shouldRestart(afterExitAt: nextStart.addingTimeInterval(0.5)))
        }
        let finalStart = start.addingTimeInterval(6)
        policy.recordStart(at: finalStart)
        XCTAssertFalse(
            policy.shouldRestart(afterExitAt: finalStart.addingTimeInterval(0.5)))
    }

    func testReadableTerminalUsesStrongerTintThanCompactPanels() {
        let compact = PanelAppearance.tintOpacity(base: 0.65, presentation: .compact)
        let readable = PanelAppearance.tintOpacity(base: 0.65, presentation: .readable)

        XCTAssertEqual(compact, 0.247, accuracy: 0.001)
        XCTAssertEqual(readable, 0.82, accuracy: 0.001)
        XCTAssertGreaterThan(readable, compact)
    }

    func testUsagePanelAcceptsContextMenuWithoutTakingKeyboardFocus() throws {
        let previousConfiguration = PanelSettings.deckConfiguration
        let previousRight = PanelSettings.activeModule(on: .right)
        defer {
            PanelSettings.deckConfiguration = previousConfiguration
            PanelSettings.setActiveModule(previousRight, on: .right)
        }
        PanelSettings.deckConfiguration = .legacy(
            order: .terminalLeft, enabledPanels: .all)
        PanelSettings.setActiveModule(.usage, on: .right)

        let controller = makeReadOnlyDeckController(side: .right)
        let menu = try XCTUnwrap(controller.panel.contentView?.menu)

        controller.menuWillOpen(menu)

        XCTAssertFalse(controller.panel.ignoresMouseEvents)
        XCTAssertFalse(controller.panel.canBecomeKey)
        XCTAssertEqual(
            menu.items.filter { !$0.isSeparatorItem }.map(\.title),
            [
                "Settings…", "Show Used Values", "Move Terminal to Right",
                "Refresh Modules & Layout",
            ])
    }

    func testReadOnlyDeckRebuildsOnlyWhenActiveModuleChanges() {
        let previousConfiguration = PanelSettings.deckConfiguration
        let previousRight = PanelSettings.activeModule(on: .right)
        defer {
            PanelSettings.deckConfiguration = previousConfiguration
            PanelSettings.setActiveModule(previousRight, on: .right)
        }
        PanelSettings.deckConfiguration = PanelDeckConfiguration(
            left: [.terminal], right: [.usage, .systemStats],
            enabled: [.terminal, .usage, .systemStats])
        PanelSettings.setActiveModule(.usage, on: .right)
        let controller = makeReadOnlyDeckController(side: .right)

        XCTAssertFalse(controller.synchronizeActiveModule())

        PanelSettings.setActiveModule(.systemStats, on: .right)

        XCTAssertTrue(controller.synchronizeActiveModule())
        XCTAssertEqual(controller.activeModule, .systemStats)
        XCTAssertFalse(controller.synchronizeActiveModule())
    }

    private func makeReadOnlyDeckController(side: PanelSide) -> ReadOnlyDeckPanelController {
        ReadOnlyDeckPanelController(
            initialFrame: NSRect(x: 0, y: 0, width: 214, height: 59),
            theme: Theme.theme(id: ""),
            usageStore: UsageStore(),
            systemStatsStore: SystemStatsStore(),
            serviceMonitorStore: ServiceMonitorStore(),
            weatherStore: WeatherStore(),
            scheduleStore: ScheduleStore(),
            clockStore: ClockStore(),
            batteryStore: BatteryStore(),
            networkStore: NetworkStore(),
            menuTarget: NSObject(),
            side: side)
    }

    private func makeSettingsModel(
        configuration: PanelDeckConfiguration
    ) -> SettingsPanelModel {
        SettingsPanelModel(
            selectedPane: .decks,
            values: makeSettingsValues(configuration: configuration),
            fontNames: ["Menlo"])
    }

    private func makeSettingsValues(
        configuration: PanelDeckConfiguration
    ) -> SettingsPanelValues {
        SettingsPanelValues(
            deckConfiguration: configuration,
            terminal: TerminalSettingsState(
                focusWidthMultiplier: 2, focusHeightMultiplier: 4,
                fontName: "Menlo"),
            usage: UsageSettingsState(
                enabledProviders: UsageProviderID.allCases,
                fontName: "Menlo", fontSize: 10,
                displayMode: .remaining, textColor: .theme),
            systemStats: SystemStatsSettingsState(
                refreshInterval: 2, metrics: SystemStatsMetric.defaultSelection),
            serviceMonitor: ServiceMonitorSettingsState(
                endpoints: [], refreshInterval: 30),
            weather: WeatherSettingsState(
                location: nil, temperatureUnit: .celsius, refreshInterval: 1_800),
            schedule: ScheduleSettingsState(
                calendarIDs: [], includeAllDay: false, refreshInterval: 300),
            clock: ClockSettingsState(
                timeZoneIdentifier: ClockTimeZone.systemIdentifier, hourFormat: .system),
            battery: BatterySettingsState(refreshInterval: 60),
            network: NetworkSettingsState(refreshInterval: 2),
            appearance: AppearanceSettingsState(
                cornerRadius: 10, tintOpacity: 0.6))
    }
}
