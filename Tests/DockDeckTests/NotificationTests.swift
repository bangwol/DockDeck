import XCTest

@testable import DockDeck

final class NotificationTests: XCTestCase {
    func testUsageAlertsOnlyWhenLiveWindowCrossesThreshold() {
        var detector = DockNotificationEventDetector()
        let low = provider(usedPercent: 85)
        let recovered = provider(usedPercent: 70)

        XCTAssertEqual(
            detector.usageEvents(
                providers: [low], remainingThreshold: 20, enabled: true).count,
            1)
        XCTAssertTrue(
            detector.usageEvents(
                providers: [low], remainingThreshold: 20, enabled: true).isEmpty)
        XCTAssertTrue(
            detector.usageEvents(
                providers: [recovered], remainingThreshold: 20, enabled: true).isEmpty)
        XCTAssertEqual(
            detector.usageEvents(
                providers: [low], remainingThreshold: 20, enabled: true).count,
            1)

        let stale = ProviderUsage(
            id: .codex, name: "CODEX", windows: low.windows,
            freshness: .stale, detail: nil)
        XCTAssertTrue(
            detector.usageEvents(
                providers: [stale], remainingThreshold: 20, enabled: true).isEmpty)
    }

    func testServiceAlertsTrackFailureAndRecoveryTransitions() {
        var detector = DockNotificationEventDetector()
        let endpoint = ServiceMonitorEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "API", urlString: "https://example.com")

        XCTAssertTrue(
            detector.serviceEvents(
                items: [ServiceMonitorItem(endpoint: endpoint, state: .checking)],
                failuresEnabled: true, recoveriesEnabled: true).isEmpty)
        XCTAssertEqual(
            detector.serviceEvents(
                items: [ServiceMonitorItem(endpoint: endpoint, state: .down("Timed out"))],
                failuresEnabled: true, recoveriesEnabled: true).first?.title,
            "API is unavailable")
        XCTAssertTrue(
            detector.serviceEvents(
                items: [ServiceMonitorItem(endpoint: endpoint, state: .down("Timed out"))],
                failuresEnabled: true, recoveriesEnabled: true).isEmpty)
        XCTAssertEqual(
            detector.serviceEvents(
                items: [
                    ServiceMonitorItem(
                        endpoint: endpoint,
                        state: .up(statusCode: 204, latencyMilliseconds: 42))
                ],
                failuresEnabled: true, recoveriesEnabled: true).first?.title,
            "API recovered")
    }

    func testBatteryAlertOnlyEntersLowStateWhileDischarging() {
        var detector = DockNotificationEventDetector()

        XCTAssertTrue(
            detector.batteryEvents(
                snapshot: BatterySnapshot(
                    percent: 18, state: .charging, minutesRemaining: nil),
                remainingThreshold: 20, enabled: true).isEmpty)
        XCTAssertEqual(
            detector.batteryEvents(
                snapshot: BatterySnapshot(
                    percent: 18, state: .discharging, minutesRemaining: 60),
                remainingThreshold: 20, enabled: true).count,
            1)
        XCTAssertTrue(
            detector.batteryEvents(
                snapshot: BatterySnapshot(
                    percent: 17, state: .discharging, minutesRemaining: 55),
                remainingThreshold: 20, enabled: true).isEmpty)
    }

    func testCoordinatorRequestsPermissionOnlyAfterExplicitCall() {
        let delivery = FakeNotificationDelivery(
            status: .notDetermined, requestedStatus: .authorized)
        var settings = DockNotificationSettings()
        settings.enabled = true
        let coordinator = DockNotificationCoordinator(
            settings: settings, delivery: delivery)

        coordinator.refreshAuthorizationStatus()
        coordinator.observeUsage([provider(usedPercent: 85)])

        XCTAssertEqual(delivery.requestCount, 0)
        XCTAssertTrue(delivery.delivered.isEmpty)

        coordinator.requestAuthorization()

        XCTAssertEqual(delivery.requestCount, 1)
        XCTAssertEqual(delivery.delivered.count, 1)
        XCTAssertEqual(coordinator.authorizationStatus, .authorized)
    }

    func testNotificationThresholdsNormalizeToSupportedValues() {
        var settings = DockNotificationSettings()
        settings.usageRemainingThreshold = 26
        settings.batteryRemainingThreshold = -1

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.usageRemainingThreshold, 30)
        XCTAssertEqual(normalized.batteryRemainingThreshold, 10)
    }

    func testNotificationSettingsDecodeMissingRulesWithSafeDefaults() throws {
        let settings = try JSONDecoder().decode(
            DockNotificationSettings.self,
            from: Data(#"{"enabled":true}"#.utf8))

        XCTAssertTrue(settings.enabled)
        XCTAssertTrue(settings.usageAlerts)
        XCTAssertTrue(settings.serviceFailureAlerts)
        XCTAssertTrue(settings.serviceRecoveryAlerts)
        XCTAssertTrue(settings.batteryAlerts)
        XCTAssertTrue(settings.focusTimerAlerts)
    }

    func testFocusCompletionUsesTheAuthorizedNotificationPipeline() {
        let delivery = FakeNotificationDelivery(
            status: .authorized, requestedStatus: .authorized)
        var settings = DockNotificationSettings()
        settings.enabled = true
        let coordinator = DockNotificationCoordinator(
            settings: settings, delivery: delivery)
        coordinator.refreshAuthorizationStatus()

        coordinator.notifyFocusTimerCompleted(
            .focus, now: Date(timeIntervalSince1970: 10_000))

        XCTAssertEqual(delivery.delivered.first?.title, "Focus complete")
        XCTAssertEqual(
            delivery.delivered.first?.identifier,
            "dockdeck.focus.focus.10000")
    }

    private func provider(usedPercent: Double) -> ProviderUsage {
        ProviderUsage(
            id: .codex,
            name: "CODEX",
            windows: [
                UsageWindow(
                    durationMinutes: 7 * 24 * 60,
                    usedPercent: usedPercent,
                    resetsAt: Date(timeIntervalSince1970: 2_000_000_000))
            ],
            freshness: .live,
            detail: nil)
    }
}

private final class FakeNotificationDelivery: DockNotificationDelivering {
    let status: DockNotificationAuthorizationStatus
    let requestedStatus: DockNotificationAuthorizationStatus
    private(set) var requestCount = 0
    private(set) var delivered: [DockNotificationEvent] = []

    init(
        status: DockNotificationAuthorizationStatus,
        requestedStatus: DockNotificationAuthorizationStatus
    ) {
        self.status = status
        self.requestedStatus = requestedStatus
    }

    func authorizationStatus(
        completion: @escaping (DockNotificationAuthorizationStatus) -> Void
    ) {
        completion(status)
    }

    func requestAuthorization(
        completion: @escaping (DockNotificationAuthorizationStatus) -> Void
    ) {
        requestCount += 1
        completion(requestedStatus)
    }

    func deliver(_ event: DockNotificationEvent) {
        delivered.append(event)
    }
}
