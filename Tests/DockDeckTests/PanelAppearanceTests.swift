import Cocoa
import SwiftUI
import XCTest

@testable import DockDeck

final class PanelAppearanceTests: XCTestCase {
    func testReadableCompactTypeKeepsTenPointFloorWithoutShrinkingLargerText() {
        XCTAssertEqual(CompactReadability.size(7.5, enabled: false), 7.5)
        XCTAssertEqual(CompactReadability.size(7.5, enabled: true), 10)
        XCTAssertEqual(CompactReadability.size(20, enabled: true), 20)
    }

    func testTextTileExampleSurvivesArgumentEditing() throws {
        let model = makeSettingsModel(configuration: .legacy(order: .terminalLeft, enabledPanels: .all))
        model.useCustomTileExample(json: false)
        model.setCustomTileArguments(model.customTileConfiguration.arguments.joined(separator: "\n"))
        let snapshot = try CustomTileClient().read(configuration: model.customTileConfiguration, now: Date())
        XCTAssertEqual(snapshot.content.value, "Ready")
        XCTAssertEqual(snapshot.content.detail, "Example output")
    }

    func testCustomTileSlotsCanBeConfiguredIndependentlyWhileDisabled() {
        let model = makeSettingsModel(configuration: .legacy(order: .terminalLeft, enabledPanels: .all))
        let original = model.values.customTile
        model.selectedPane = .customTile2
        model.setCustomTileTitle("Build two")
        model.useCustomTileExample(json: true)
        XCTAssertEqual(model.values.customTile, original)
        XCTAssertEqual(model.values.extraCustomTiles[.customTile2]?.title, "Build two")
        XCTAssertEqual(model.values.extraCustomTiles[.customTile2]?.executablePath, "/usr/bin/printf")
        XCTAssertFalse(model.values.deckConfiguration.enabled.contains(.customTile2))
        model.selectedPane = .customTile3
        XCTAssertEqual(model.customTileConfiguration.title, "Custom Tile 3")
        XCTAssertFalse(model.customTileConfiguration.isConfigured)
    }

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
                .usage, .systemStats, .serviceMonitor, .weather, .schedule, .clock, .music,
                .battery, .network, .localPorts,
                .projectPulse,
                .githubInbox,
                .docker,
                .customTile, .customTile2, .customTile3,
                .focusTimer,
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
                .usage, .systemStats, .serviceMonitor, .weather, .schedule, .clock, .music,
                .battery, .network, .localPorts,
                .projectPulse,
                .githubInbox,
                .docker,
                .customTile, .customTile2, .customTile3,
                .focusTimer,
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
                .usage, .serviceMonitor, .weather, .schedule, .clock, .music, .battery,
                .network, .localPorts,
                .projectPulse,
                .githubInbox,
                .docker,
                .customTile, .customTile2, .customTile3,
                .focusTimer,
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

    func testDeckAutoSlideSettingsNormalizeSelectionsAndInterval() throws {
        let futureModule = PanelModuleID(rawValue: "future-module")
        let settings = DeckAutoSlideSettings(
            modules: [.terminal, .usage, .usage, futureModule], interval: 1)
        let decoded = try JSONDecoder().decode(
            DeckAutoSlideSettings.self,
            from: Data(#"{"modules":["weather"]}"#.utf8))

        XCTAssertEqual(settings.modules, [.terminal, .usage, futureModule])
        XCTAssertEqual(settings.interval, DeckAutoSlideSettings.minimumInterval)
        XCTAssertEqual(decoded.modules, [.weather])
        XCTAssertEqual(decoded.interval, DeckAutoSlideSettings.defaultInterval)
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
                .usage, .systemStats, .serviceMonitor, .weather, .schedule, .clock, .music,
                .battery, .network, .localPorts,
                .projectPulse,
                .githubInbox,
                .docker,
                .customTile, .customTile2, .customTile3,
                .focusTimer,
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

    func testDeckEditorSeparatesActiveAndInactiveModules() {
        let model = makeSettingsModel(
            configuration: PanelDeckConfiguration(
                left: [.terminal, .weather],
                right: [.usage, .battery],
                enabled: [.terminal, .usage]))

        XCTAssertEqual(model.enabledModuleDefinitions(on: .left).map(\.id), [.terminal])
        XCTAssertEqual(model.enabledModuleDefinitions(on: .right).map(\.id), [.usage])
        XCTAssertTrue(model.inactiveModuleDefinitions.map(\.id).contains(.weather))
        XCTAssertTrue(model.inactiveModuleDefinitions.map(\.id).contains(.battery))
        XCTAssertTrue(model.inactiveModuleDefinitions.allSatisfy { !model.isEnabled($0.id) })
    }

    func testShowPlacesInactiveModuleInShorterDeckWithLeftTieBreak() {
        let model = makeSettingsModel(
            configuration: PanelDeckConfiguration(
                left: [.terminal, .weather],
                right: [.usage, .clock],
                enabled: [.terminal, .usage]))

        model.setEnabled(true, for: .weather)

        XCTAssertEqual(model.side(containing: .weather), .left)
        XCTAssertTrue(model.isEnabled(.weather))

        model.setEnabled(true, for: .clock)

        XCTAssertEqual(model.side(containing: .clock), .right)
        XCTAssertTrue(model.isEnabled(.clock))
        XCTAssertEqual(model.recentlyActivatedModule, .clock)
    }

    func testDroppingInactiveModuleIntoDeckActivatesAtTarget() {
        let model = makeSettingsModel(
            configuration: PanelDeckConfiguration(
                left: [.terminal],
                right: [.usage, .weather],
                enabled: [.terminal, .usage]))

        model.activateModule(.weather, on: .left, before: .terminal)

        XCTAssertEqual(model.enabledModuleDefinitions(on: .left).map(\.id), [.weather, .terminal])
        XCTAssertTrue(model.isEnabled(.weather))
        XCTAssertEqual(model.recentlyActivatedModule, .weather)
    }

    func testModuleAndSettingsSearchRetainEnabledBoundsAndKeyboardSelection() {
        let configuration = PanelDeckConfiguration(left: [.terminal], right: [.usage, .weather], enabled: [.terminal, .usage])
        let picker = ModulePickerModel(configuration: configuration, active: [.terminal])
        XCTAssertEqual(picker.modules.map(\.id), [.terminal, .usage])
        picker.move(1)
        XCTAssertEqual(picker.selection, .usage)
        picker.move(Int.max)
        XCTAssertEqual(picker.selection, .usage)
        picker.query = "CLAUDE limits"
        XCTAssertEqual(picker.modules.map(\.id), [.usage])
        picker.query = "weather"
        XCTAssertNil(picker.selection)
        picker.move(-1)
        XCTAssertNil(picker.selection)
        let settings = makeSettingsModel(configuration: configuration)
        XCTAssertEqual(settings.sidebarSections(matching: "selected city").flatMap(\.panes), [.weather])
        XCTAssertTrue(settings.sidebarSections(matching: "absentword").isEmpty)
    }

    func testSettingsSidebarSortsEnabledModulesThenTitlesWithoutChangingDeckOrder() {
        let model = makeSettingsModel(
            configuration: PanelDeckConfiguration(
                left: [.weather, .terminal, .battery],
                right: [.usage, .docker, .clock],
                enabled: [.usage, .battery, .terminal]))

        XCTAssertEqual(
            model.moduleDefinitions.map(\.id),
            [
                .battery, .terminal, .usage,
                .customTile, .customTile2, .customTile3, .docker, .focusTimer, .githubInbox, .localPorts, .music, .network,
                .projectPulse, .schedule, .serviceMonitor, .systemStats, .weather, .clock,
            ])
        XCTAssertEqual(
            model.moduleDefinitions(on: .left).map(\.id),
            [.terminal, .battery, .weather])
    }

    func testSettingsModelDoesNotRepublishNoOpDeckMove() {
        let model = makeSettingsModel(
            configuration: PanelDeckConfiguration(
                left: [.terminal], right: [.usage, .systemStats],
                enabled: [.terminal, .usage, .systemStats]))
        var callbackCount = 0
        model.onChange = { _ in callbackCount += 1 }

        model.moveModule(.usage, to: .right, before: .systemStats)

        XCTAssertEqual(callbackCount, 0)
    }

    func testSettingsModelUpdatesAutoSlideAndClearsHiddenModules() {
        let model = makeSettingsModel(
            configuration: PanelDeckConfiguration(
                left: [.terminal], right: [.usage, .weather],
                enabled: [.terminal, .usage, .weather]))
        var emittedSettings: [DeckAutoSlideSettings] = []
        model.onChange = {
            if case .deckAutoSlide(let settings) = $0 { emittedSettings.append(settings) }
        }

        model.setAutoSlideEnabled(true, for: .terminal)
        model.setAutoSlideEnabled(true, for: .usage)
        model.setAutoSlideEnabled(true, for: .weather)
        model.setAutoSlideInterval(7.4)
        model.setEnabled(false, for: .weather)

        XCTAssertEqual(model.values.deckAutoSlide.modules, [.terminal, .usage])
        XCTAssertEqual(model.values.deckAutoSlide.interval, 7)
        XCTAssertEqual(emittedSettings.count, 5)
        XCTAssertEqual(emittedSettings.last?.modules, [.terminal, .usage])
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
                .decks, .notifications, .diagnostics, .terminal, .usage, .battery,
                .customTile, .customTile2, .customTile3, .docker, .focusTimer, .githubInbox, .localPorts, .music, .network,
                .projectPulse, .schedule, .serviceMonitor, .systemStats, .weather,
                .clock, .appearance,
            ])
        XCTAssertEqual(model.moduleDefinition(for: .usage)?.id, .usage)
        XCTAssertEqual(model.moduleDefinition(for: .systemStats)?.id, .systemStats)
        XCTAssertEqual(model.moduleDefinition(for: .serviceMonitor)?.id, .serviceMonitor)
        XCTAssertEqual(model.moduleDefinition(for: .weather)?.id, .weather)
        XCTAssertEqual(model.moduleDefinition(for: .schedule)?.id, .schedule)
        XCTAssertEqual(model.moduleDefinition(for: .clock)?.id, .clock)
        XCTAssertEqual(model.moduleDefinition(for: .music)?.id, .music)
        XCTAssertEqual(model.moduleDefinition(for: .battery)?.id, .battery)
        XCTAssertEqual(model.moduleDefinition(for: .network)?.id, .network)
        XCTAssertEqual(model.moduleDefinition(for: .projectPulse)?.id, .projectPulse)
        XCTAssertEqual(model.moduleDefinition(for: .githubInbox)?.id, .githubInbox)
        XCTAssertEqual(model.moduleDefinition(for: .docker)?.id, .docker)
        XCTAssertEqual(model.moduleDefinition(for: .customTile)?.id, .customTile)
        XCTAssertEqual(model.moduleDefinition(for: .focusTimer)?.id, .focusTimer)
        XCTAssertEqual(model.sidebarSections.map(\.id), [.general, .modules, .interface])
        XCTAssertEqual(model.sidebarSections[0].panes, [.decks, .notifications, .diagnostics])
        XCTAssertEqual(
            model.sidebarSections[1].panes,
            model.moduleDefinitions.compactMap(\.settingsPane))
        XCTAssertEqual(model.sidebarSections[2].panes, [.appearance])
    }

    func testEveryBuiltInModuleHasMetadataAndRuntime() {
        XCTAssertEqual(PanelModuleRegistry.all.map(\.id), PanelModuleID.builtIns)
        let services = PanelModuleServices()
        for module in PanelModuleID.readOnlyBuiltIns {
            XCTAssertNotNil(services.runtime(for: module), module.rawValue)
        }
    }

    func testDiagnosticsPreserveLastSuccessAcrossFailure() {
        let previousDate = Date(timeIntervalSince1970: 1_000)
        let checkedDate = Date(timeIntervalSince1970: 2_000)
        let previous = DiagnosticCheckItem(
            id: .github, title: "GitHub CLI", symbolName: "point.3.connected.trianglepath.dotted",
            state: .ready, detail: "Installed and signed in", checkedAt: previousDate,
            lastSuccessfulAt: previousDate)
        let failed = DiagnosticCheckItem(
            id: .github, title: "GitHub CLI", symbolName: "point.3.connected.trianglepath.dotted",
            state: .warning, detail: "Installed; sign-in required", checkedAt: checkedDate,
            lastSuccessfulAt: nil)

        let merged = DiagnosticsStore.merging([failed], previous: [previous])

        XCTAssertEqual(merged.first?.checkedAt, checkedDate)
        XCTAssertEqual(merged.first?.lastSuccessfulAt, previousDate)
    }

    func testDiagnosticsReportOmitsUntrustedDetails() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let item = DiagnosticCheckItem(
            id: .github, title: "ignored", symbolName: "ignored", state: .warning,
            detail: "token ghp_secret at /Users/private/project", checkedAt: date,
            lastSuccessfulAt: nil)
        let runtime = ModuleRuntimeDiagnostics(
            states: [.githubInbox: .background], systemActive: true,
            constrained: true, stateChangedAt: [.githubInbox: date])

        let report = DiagnosticsReportBuilder.build(
            items: [item], runtime: runtime, appVersion: "0.1.1",
            operatingSystem: "macOS 15.6", architecture: "arm64")

        XCTAssertTrue(report.contains("GitHub CLI: check"))
        XCTAssertTrue(report.contains("GitHub Inbox: background"))
        XCTAssertTrue(report.contains("Cadence: reduced"))
        XCTAssertFalse(report.contains("ghp_secret"))
        XCTAssertFalse(report.contains("/Users/private"))
        XCTAssertFalse(report.contains("ignored"))
    }

    func testDiagnosticCommandRunnerReportsExitStatus() {
        XCTAssertEqual(
            DiagnosticCommandRunner.exitsSuccessfully(
                URL(fileURLWithPath: "/usr/bin/true"), arguments: []),
            true)
        XCTAssertEqual(
            DiagnosticCommandRunner.exitsSuccessfully(
                URL(fileURLWithPath: "/usr/bin/false"), arguments: []),
            false)
    }

    func testDiagnosticCommandRunnerResolvesSiblingRuntime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DockDeckDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("diagnostic-helper")
        let wrapper = directory.appendingPathComponent("diagnostic-wrapper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try Data("#!/bin/sh\ndiagnostic-helper\n".utf8).write(to: wrapper)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: helper.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: wrapper.path)

        XCTAssertEqual(
            DiagnosticCommandRunner.exitsSuccessfully(
                wrapper, arguments: [], environment: ["PATH": "/usr/bin:/bin"]),
            true)
    }

    func testModuleRuntimeCoordinatorStartsAndStopsOnlyChangedModules() {
        let coordinator = ModuleRuntimeCoordinator()
        var terminalStarts = 0
        var terminalStops = 0
        var usageStarts = 0
        var usageStops = 0
        var usageActivities: [(ModuleRuntimeActivity, Bool)] = []
        coordinator.register(
            .terminal, start: { terminalStarts += 1 }, stop: { terminalStops += 1 })
        coordinator.register(
            .usage,
            start: { usageStarts += 1 },
            stop: { usageStops += 1 },
            updateActivity: { usageActivities.append(($0, $1)) })

        coordinator.synchronize(
            enabledModules: [.terminal, .usage], visibleModules: [.terminal])
        coordinator.synchronize(
            enabledModules: [.terminal, .usage], visibleModules: [.terminal])
        coordinator.synchronize(
            enabledModules: [.terminal, .usage], visibleModules: [.usage],
            lowPowerMode: true)
        coordinator.synchronize(
            enabledModules: [.usage, PanelModuleID(rawValue: "future")],
            visibleModules: [.usage], lowPowerMode: true)
        coordinator.stopAll()

        XCTAssertEqual(terminalStarts, 1)
        XCTAssertEqual(terminalStops, 1)
        XCTAssertEqual(usageStarts, 1)
        XCTAssertEqual(usageStops, 1)
        XCTAssertEqual(coordinator.state(for: .terminal), .stopped)
        XCTAssertEqual(coordinator.state(for: .usage), .stopped)
        XCTAssertEqual(usageActivities.count, 2)
        XCTAssertEqual(usageActivities[0].0, .background)
        XCTAssertFalse(usageActivities[0].1)
        XCTAssertEqual(usageActivities[1].0, .visible)
        XCTAssertTrue(usageActivities[1].1)
    }

    func testModuleRuntimeDiagnosticsTrackStateChangeTime() {
        var time = Date(timeIntervalSince1970: 100)
        let coordinator = ModuleRuntimeCoordinator(now: { time })
        coordinator.register(.usage, start: {}, stop: {})

        XCTAssertEqual(coordinator.diagnostics().stateChangedAt[.usage], time)
        time = Date(timeIntervalSince1970: 200)
        coordinator.synchronize(enabledModules: [.usage], visibleModules: [.usage])
        XCTAssertEqual(coordinator.diagnostics().stateChangedAt[.usage], time)
        time = Date(timeIntervalSince1970: 300)
        coordinator.synchronize(enabledModules: [.usage], visibleModules: [.usage])
        XCTAssertEqual(
            coordinator.diagnostics().stateChangedAt[.usage],
            Date(timeIntervalSince1970: 200))
    }

    func testModuleRuntimeCoordinatorSuspendsBackgroundWorkAndPreservesTerminal() {
        let coordinator = ModuleRuntimeCoordinator()
        var starts: [PanelModuleID] = []
        var terminalStops = 0
        var usageStops = 0
        coordinator.register(
            .terminal, start: { starts.append(.terminal) },
            stop: { terminalStops += 1 }, suspendsWhenInactive: false)
        coordinator.register(
            .usage, start: { starts.append(.usage) }, stop: { usageStops += 1 })

        coordinator.synchronize(
            enabledModules: [.terminal, .usage], visibleModules: [.terminal])
        coordinator.synchronize(
            enabledModules: [.terminal, .usage], visibleModules: [.terminal],
            systemActive: false)

        XCTAssertEqual(starts, [.terminal, .usage])
        XCTAssertEqual(terminalStops, 0)
        XCTAssertEqual(usageStops, 1)
        XCTAssertEqual(coordinator.state(for: .terminal), .visible)
        XCTAssertEqual(coordinator.state(for: .usage), .suspended)
        let diagnostics = coordinator.diagnostics()
        XCTAssertEqual(
            diagnostics.states, [.terminal: .visible, .usage: .suspended])
        XCTAssertFalse(diagnostics.systemActive)
        XCTAssertFalse(diagnostics.constrained)
        XCTAssertNotNil(diagnostics.stateChangedAt[.terminal])
        XCTAssertNotNil(diagnostics.stateChangedAt[.usage])

        coordinator.synchronize(
            enabledModules: [.terminal, .usage], visibleModules: [.usage])

        XCTAssertEqual(starts, [.terminal, .usage, .usage])
        XCTAssertEqual(coordinator.state(for: .terminal), .background)
        XCTAssertEqual(coordinator.state(for: .usage), .visible)
        XCTAssertTrue(coordinator.diagnostics().systemActive)
    }

    func testModuleRuntimePolicyCombinesPowerAndThermalPressure() {
        XCTAssertFalse(ModuleRuntimePolicy.isConstrained(
            lowPowerMode: false, thermalState: .nominal))
        XCTAssertFalse(ModuleRuntimePolicy.isConstrained(
            lowPowerMode: false, thermalState: .fair))
        XCTAssertTrue(ModuleRuntimePolicy.isConstrained(
            lowPowerMode: false, thermalState: .serious))
        XCTAssertTrue(ModuleRuntimePolicy.isConstrained(
            lowPowerMode: false, thermalState: .critical))
        XCTAssertTrue(ModuleRuntimePolicy.isConstrained(
            lowPowerMode: true, thermalState: .nominal))
    }

    func testModuleRefreshCadenceCombinesVisibilityAndLowPower() {
        var cadence = ModuleRefreshCadence(backgroundMultiplier: 4)

        XCTAssertEqual(cadence.effectiveInterval(configuredInterval: 2), 2)
        XCTAssertTrue(cadence.update(activity: .background, lowPowerMode: false))
        XCTAssertEqual(cadence.effectiveInterval(configuredInterval: 2), 8)
        XCTAssertTrue(cadence.update(activity: .background, lowPowerMode: true))
        XCTAssertEqual(cadence.effectiveInterval(configuredInterval: 2), 16)
        XCTAssertFalse(cadence.update(activity: .background, lowPowerMode: true))
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

    func testSettingsModelEmitsClaudeRefreshModeChange() {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))
        var emittedMode: ClaudeUsageRefreshMode?
        model.onChange = {
            if case .usage(.claudeRefreshMode(let mode)) = $0 { emittedMode = mode }
        }

        model.setClaudeUsageRefreshMode(.statusLineOnly)

        XCTAssertEqual(model.values.usage.claudeRefreshMode, .statusLineOnly)
        XCTAssertEqual(emittedMode, .statusLineOnly)
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

    func testAutoSlidePlansBothDecksOnTheSameTick() {
        let configuration = PanelDeckConfiguration(
            left: [.usage, .weather, .battery],
            right: [.systemStats, .clock, .terminal],
            enabled: [.usage, .weather, .battery, .systemStats, .clock, .terminal])
        let settings = DeckAutoSlideSettings(
            modules: [.usage, .battery, .systemStats, .clock], interval: 10)

        let synchronizedSteps = DeckAutoSlidePlanner.steps(
            settings: settings,
            configuration: configuration,
            activeModule: { side in side == .left ? .usage : .systemStats })
        XCTAssertEqual(
            synchronizedSteps,
            [
                DeckAutoSlideStep(side: .left, module: .battery),
                DeckAutoSlideStep(side: .right, module: .clock),
            ])

        let manualLeftSteps = DeckAutoSlidePlanner.steps(
            settings: settings,
            configuration: configuration,
            activeModule: { side in side == .left ? .weather : .systemStats })
        XCTAssertEqual(
            manualLeftSteps,
            [DeckAutoSlideStep(side: .right, module: .clock)])
    }

    func testAutoSlideCanCycleIntoAndOutOfTerminal() {
        let configuration = PanelDeckConfiguration(
            left: [.terminal, .weather], right: [.usage],
            enabled: [.terminal, .weather, .usage])
        let settings = DeckAutoSlideSettings(modules: [.terminal, .weather])

        XCTAssertEqual(
            DeckAutoSlidePlanner.steps(
                settings: settings,
                configuration: configuration,
                activeModule: { $0 == .left ? .weather : .usage }),
            [DeckAutoSlideStep(side: .left, module: .terminal)])
        XCTAssertEqual(
            DeckAutoSlidePlanner.steps(
                settings: settings,
                configuration: configuration,
                activeModule: { $0 == .left ? .terminal : .usage }),
            [DeckAutoSlideStep(side: .left, module: .weather)])
    }

    func testTerminalAutoSlideRequiresCompactIdlePanel() {
        XCTAssertFalse(
            TerminalAutoSlidePolicy.blocksAdvance(
                mode: .docked, panelIsVisible: true,
                panelIsKey: false, pointerInside: false))
        XCTAssertTrue(
            TerminalAutoSlidePolicy.blocksAdvance(
                mode: .focused, panelIsVisible: true,
                panelIsKey: false, pointerInside: false))
        XCTAssertTrue(
            TerminalAutoSlidePolicy.blocksAdvance(
                mode: .large, panelIsVisible: true,
                panelIsKey: false, pointerInside: false))
        XCTAssertTrue(
            TerminalAutoSlidePolicy.blocksAdvance(
                mode: .docked, panelIsVisible: false,
                panelIsKey: false, pointerInside: false))
        XCTAssertTrue(
            TerminalAutoSlidePolicy.blocksAdvance(
                mode: .docked, panelIsVisible: true,
                panelIsKey: true, pointerInside: false))
        XCTAssertTrue(
            TerminalAutoSlidePolicy.blocksAdvance(
                mode: .docked, panelIsVisible: true,
                panelIsKey: false, pointerInside: true))
    }

    func testDeckScrollDirectionUsesVerticalAxis() {
        XCTAssertEqual(
            DeckScrollDirection.resolved(deltaX: 0, deltaY: 1), .previous)
        XCTAssertEqual(
            DeckScrollDirection.resolved(deltaX: 0, deltaY: -1), .next)
        XCTAssertNil(DeckScrollDirection.resolved(deltaX: 2, deltaY: 1))
        XCTAssertNil(DeckScrollDirection.resolved(deltaX: 0, deltaY: 0))
    }

    func testDeckTransitionDirectionAndReduceMotionPlan() {
        XCTAssertEqual(
            DeckTransitionPlan.resolved(direction: .next, reduceMotion: false),
            DeckTransitionPlan(insertionEdge: .bottom, removalEdge: .top))
        XCTAssertEqual(
            DeckTransitionPlan.resolved(direction: .previous, reduceMotion: false),
            DeckTransitionPlan(insertionEdge: .top, removalEdge: .bottom))
        XCTAssertNil(DeckTransitionPlan.resolved(direction: .next, reduceMotion: true))
    }

    func testDeckPresentationShowsCurrentPageDuringSelection() {
        let presentation = ReadOnlyDeckPresentation(
            activeModule: .usage, theme: Theme.theme(id: ""))

        presentation.select(
            .weather,
            direction: .next,
            enabledModules: [.usage, .weather, .clock],
            showsIndicator: true)

        XCTAssertEqual(presentation.activeModule, .weather)
        XCTAssertEqual(presentation.direction, .next)
        XCTAssertEqual(presentation.pageIndicator, "2/3")
    }

    func testAutomaticDeckSelectionHidesPageIndicator() {
        let previousConfiguration = PanelSettings.deckConfiguration
        let previousRight = PanelSettings.activeModule(on: .right)
        defer {
            PanelSettings.deckConfiguration = previousConfiguration
            PanelSettings.setActiveModule(previousRight, on: .right)
        }
        PanelSettings.deckConfiguration = PanelDeckConfiguration(
            left: [.terminal], right: [.usage, .weather],
            enabled: [.terminal, .usage, .weather])
        PanelSettings.setActiveModule(.usage, on: .right)
        let controller = makeReadOnlyDeckController(side: .right)

        controller.selectForAutoSlide(.weather)

        XCTAssertEqual(controller.activeModule, .weather)
        XCTAssertNil(controller.pageIndicatorForTesting)

        controller.select(.usage)

        XCTAssertEqual(controller.pageIndicatorForTesting, "1/2")
    }

    func testTerminalScrollUsesDeckOnlyWhileDocked() {
        XCTAssertEqual(TerminalScrollRoute.resolved(for: .docked), .deck)
        XCTAssertEqual(TerminalScrollRoute.resolved(for: .focused), .terminal)
        XCTAssertEqual(TerminalScrollRoute.resolved(for: .large), .terminal)
    }

    func testFocusedTerminalResizeUsesEightPointHitArea() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 200)

        XCTAssertEqual(
            WindowResizeGeometry.edges(at: NSPoint(x: 7, y: 100), in: bounds), .left)
        XCTAssertEqual(
            WindowResizeGeometry.edges(at: NSPoint(x: 399, y: 199), in: bounds),
            [.right, .top])
        XCTAssertTrue(
            WindowResizeGeometry.edges(at: NSPoint(x: 9, y: 100), in: bounds).isEmpty)

        let frame = WindowResizeGeometry.frame(
            from: NSRect(x: 100, y: 100, width: 400, height: 200),
            mouseDelta: NSPoint(x: -40, y: 30),
            edges: [.left, .top],
            minSize: NSSize(width: 300, height: 150),
            maxSize: NSSize(width: 800, height: 600))
        XCTAssertEqual(frame, NSRect(x: 60, y: 100, width: 440, height: 230))
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

    func testProjectPulseSettingsRenderRemoteRepository() throws {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))
        model.setProjectPulseSource(.github)
        model.setProjectPulseGitHubRepository("bangwol/DockDeck")
        let option = GitHubRepositoryOption(
            nameWithOwner: "bangwol/DockDeck",
            isPrivate: false,
            isArchived: false,
            pushedAt: nil)
        let catalog = GitHubRepositoryCatalog(
            listing: PanelFakeGitHubRepositoryListing(repositories: [option]))
        let completed = expectation(description: "Repository choices loaded")
        var fulfilled = false
        let cancellable = catalog.$status.sink { status in
            guard !fulfilled, status == .ready else { return }
            fulfilled = true
            completed.fulfill()
        }
        catalog.load()
        wait(for: [completed], timeout: 1)

        let size = NSSize(width: 540, height: 540)
        let rootView = ProjectPulseSettingsView(
            model: model, githubRepositories: catalog)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let view = NSHostingView(
            rootView: rootView)
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        cancellable.cancel()
    }

    func testProjectPulseSettingsRenderGitHubActivity() throws {
        let model = makeSettingsModel(
            configuration: .legacy(order: .terminalLeft, enabledPanels: .all))
        model.setProjectPulseSource(.github)
        model.setProjectPulseGitHubScope(.activity)
        XCTAssertEqual(model.values.projectPulse.refreshInterval, 300)

        let size = NSSize(width: 540, height: 540)
        let rootView = ProjectPulseSettingsView(model: model)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let view = NSHostingView(rootView: rootView)
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        XCTAssertEqual(view.frame.size, size)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
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

    func testProjectFolderOpeningUsesExistingDirectoriesAsNativeURLs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DockDeck folder \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(TerminalProjectFolder.existingURL(directory.path), directory)
        let file = directory.appendingPathComponent("file")
        try Data().write(to: file)
        XCTAssertNil(TerminalProjectFolder.existingURL(file.path))
        XCTAssertNil(TerminalProjectFolder.existingURL("relative/path"))
        XCTAssertNil(TerminalProjectFolder.existingURL(directory.path + "\0"))
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
                "Settings…", "Find Module…", "Open Detail…", "Show Used Values", "Move Terminal to Right",
                "Refresh Modules & Layout",
            ])
    }

    func testCompactTerminalHidesIdleScrollerUntilExpanded() throws {
        let theme = Theme.theme(id: "")
        let controller = TerminalPanelController(
            initialFrame: NSRect(x: 0, y: 0, width: 214, height: 59),
            theme: theme, menuTarget: NSObject(),
            menuAction: #selector(NSObject.isEqual(_:)))
        let scroller = try XCTUnwrap(controller.terminalView.subviews.first { $0 is NSScroller })

        XCTAssertTrue(scroller.isHidden)

        controller.applyAppearance(theme, presentation: .readable)
        XCTAssertFalse(scroller.isHidden)

        controller.applyAppearance(theme, presentation: .compact)
        XCTAssertTrue(scroller.isHidden)
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

    func testReadOnlyModuleDetailOpensAndTracksSelection() throws {
        let previousConfiguration = PanelSettings.deckConfiguration
        let previousRight = PanelSettings.activeModule(on: .right)
        defer {
            PanelSettings.deckConfiguration = previousConfiguration
            PanelSettings.setActiveModule(previousRight, on: .right)
        }
        PanelSettings.deckConfiguration = PanelDeckConfiguration(
            left: [.terminal], right: [.usage, .weather],
            enabled: [.terminal, .usage, .weather])
        PanelSettings.setActiveModule(.usage, on: .right)
        let controller = makeReadOnlyDeckController(side: .right)

        controller.showDetail()
        let detail = try XCTUnwrap(controller.detailWindowForTesting)

        XCTAssertEqual(detail.contentMinSize, ReadOnlyModuleDetailLayout.minimumSize)
        XCTAssertEqual(detail.title, "DockDeck — Usage")
        controller.select(.weather)
        XCTAssertEqual(detail.title, "DockDeck — Weather")
        detail.close()
    }

    func testReadOnlyDeckAppearanceTracksTheme() {
        let controller = makeReadOnlyDeckController(side: .right)

        controller.applyTheme(Theme.theme(id: "github-light"))
        XCTAssertEqual(
            controller.panel.appearance?.bestMatch(from: [.aqua, .darkAqua]),
            .aqua)

        controller.applyTheme(Theme.theme(id: "dracula"))
        XCTAssertEqual(
            controller.panel.appearance?.bestMatch(from: [.aqua, .darkAqua]),
            .darkAqua)
    }

    func testMajorReadOnlyModuleDetailsRender() {
        let services = PanelModuleServices()
        let theme = Theme.theme(id: "")
        let modules: [PanelModuleID] = [
            .usage, .systemStats, .serviceMonitor, .schedule,
            .music, .projectPulse, .githubInbox, .docker,
        ]

        for module in modules {
            let presentation = ReadOnlyDeckPresentation(
                activeModule: module, theme: theme)
            let view = NSHostingView(
                rootView: ReadOnlyModuleDetailView(
                    services: services, presentation: presentation))
            view.frame = NSRect(origin: .zero, size: ReadOnlyModuleDetailLayout.initialSize)
            view.layoutSubtreeIfNeeded()

            XCTAssertGreaterThan(view.fittingSize.width, 0, module.rawValue)
            XCTAssertGreaterThan(view.fittingSize.height, 0, module.rawValue)
        }
    }

    private func makeReadOnlyDeckController(side: PanelSide) -> ReadOnlyDeckPanelController {
        ReadOnlyDeckPanelController(
            initialFrame: NSRect(x: 0, y: 0, width: 214, height: 59),
            theme: Theme.theme(id: ""),
            services: PanelModuleServices(),
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
            deckAutoSlide: DeckAutoSlideSettings(),
            notifications: DockNotificationSettings(),
            terminal: TerminalSettingsState(
                focusWidthMultiplier: 2, focusHeightMultiplier: 4,
                fontName: "Menlo"),
            usage: UsageSettingsState(
                enabledProviders: UsageProviderID.allCases,
                claudeRefreshMode: .automatic,
                fontName: "Menlo", fontSize: 10,
                displayMode: .remaining, textColor: .theme, showsPace: true),
            systemStats: SystemStatsSettingsState(
                refreshInterval: 2, metrics: SystemStatsMetric.defaultSelection),
            serviceMonitor: ServiceMonitorSettingsState(
                endpoints: [], refreshInterval: 30),
            weather: WeatherSettingsState(
                location: nil, temperatureUnit: .celsius, refreshInterval: 1_800),
            schedule: ScheduleSettingsState(
                calendarIDs: [], reminderListIDs: [], includeAllDay: false,
                includeReminders: false, refreshInterval: 300),
            clock: ClockSettingsState(
                timeZoneIdentifier: ClockTimeZone.systemIdentifier, hourFormat: .system),
            battery: BatterySettingsState(refreshInterval: 60),
            network: NetworkSettingsState(refreshInterval: 2),
            projectPulse: ProjectPulseConfiguration(),
            githubInbox: GitHubInboxConfiguration(),
            docker: DockerConfiguration(),
            customTile: CustomTileConfiguration(),
            focusTimer: FocusTimerSettings(),
            appearance: AppearanceSettingsState(
                cornerRadius: 10, tintOpacity: 0.6))
    }
}

private struct PanelFakeGitHubRepositoryListing: GitHubRepositoryListing {
    let repositories: [GitHubRepositoryOption]

    func listRepositories() throws -> [GitHubRepositoryOption] {
        repositories
    }
}
