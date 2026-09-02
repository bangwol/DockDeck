import Foundation
import UserNotifications

enum DockNotificationAuthorizationStatus: Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized
}

struct DockNotificationEvent: Equatable {
    let identifier: String
    let title: String
    let body: String
}

protocol DockNotificationDelivering: AnyObject {
    func authorizationStatus(
        completion: @escaping (DockNotificationAuthorizationStatus) -> Void)
    func requestAuthorization(
        completion: @escaping (DockNotificationAuthorizationStatus) -> Void)
    func deliver(_ event: DockNotificationEvent)
}

final class SystemDockNotificationDelivery: NSObject, DockNotificationDelivering,
    UNUserNotificationCenterDelegate
{
    private let center: UNUserNotificationCenter

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func authorizationStatus(
        completion: @escaping (DockNotificationAuthorizationStatus) -> Void
    ) {
        center.getNotificationSettings { completion(Self.status(from: $0.authorizationStatus)) }
    }

    func requestAuthorization(
        completion: @escaping (DockNotificationAuthorizationStatus) -> Void
    ) {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            self?.authorizationStatus(completion: completion)
        }
    }

    func deliver(_ event: DockNotificationEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        center.add(
            UNNotificationRequest(
                identifier: event.identifier, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private static func status(
        from status: UNAuthorizationStatus
    ) -> DockNotificationAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .unknown
        }
    }
}

final class DockNotificationCoordinator {
    private let delivery: DockNotificationDelivering
    private var detector = DockNotificationEventDetector()
    private var settings: DockNotificationSettings
    private var pendingEvents: [String: DockNotificationEvent] = [:]
    private var permissionRequestInFlight = false
    private(set) var authorizationStatus: DockNotificationAuthorizationStatus = .unknown

    convenience init(settings: DockNotificationSettings = DockNotificationSettings()) {
        self.init(settings: settings, delivery: SystemDockNotificationDelivery())
    }

    init(
        settings: DockNotificationSettings,
        delivery: DockNotificationDelivering
    ) {
        self.settings = settings.normalized()
        self.delivery = delivery
    }

    func updateSettings(_ settings: DockNotificationSettings) {
        self.settings = settings.normalized()
        if !self.settings.enabled { pendingEvents.removeAll() }
    }

    func refreshAuthorizationStatus() {
        delivery.authorizationStatus { [weak self] status in
            self?.receiveAuthorizationStatus(status)
        }
    }

    /// Call only after a direct user action. DockDeck never prompts at launch.
    func requestAuthorization() {
        guard settings.enabled, !permissionRequestInFlight else { return }
        permissionRequestInFlight = true
        delivery.requestAuthorization { [weak self] status in
            self?.receiveAuthorizationStatus(status, completedRequest: true)
        }
    }

    func observeUsage(_ providers: [ProviderUsage]) {
        emit(
            detector.usageEvents(
                providers: providers,
                remainingThreshold: settings.usageRemainingThreshold,
                enabled: settings.enabled && settings.usageAlerts))
    }

    func observeServices(_ items: [ServiceMonitorItem]) {
        emit(
            detector.serviceEvents(
                items: items,
                failuresEnabled: settings.enabled && settings.serviceFailureAlerts,
                recoveriesEnabled: settings.enabled && settings.serviceRecoveryAlerts))
    }

    func observeBattery(_ snapshot: BatterySnapshot?) {
        emit(
            detector.batteryEvents(
                snapshot: snapshot,
                remainingThreshold: settings.batteryRemainingThreshold,
                enabled: settings.enabled && settings.batteryAlerts))
    }

    private func emit(_ events: [DockNotificationEvent]) {
        guard settings.enabled, !events.isEmpty else { return }
        switch authorizationStatus {
        case .authorized:
            events.forEach(delivery.deliver)
        case .unknown, .notDetermined:
            for event in events { pendingEvents[event.identifier] = event }
        case .denied:
            pendingEvents.removeAll()
        }
    }

    private func receiveAuthorizationStatus(
        _ status: DockNotificationAuthorizationStatus,
        completedRequest: Bool = false
    ) {
        let apply = { [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            if completedRequest { self.permissionRequestInFlight = false }
            guard status == .authorized, self.settings.enabled else {
                if status == .denied { self.pendingEvents.removeAll() }
                return
            }
            let events = self.pendingEvents.values.sorted {
                $0.identifier < $1.identifier
            }
            self.pendingEvents.removeAll()
            events.forEach(self.delivery.deliver)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

struct DockNotificationEventDetector {
    private struct UsageKey: Hashable {
        let provider: UsageProviderID
        let windowID: String
        let resetEpoch: Int
    }

    private enum ServiceHealth: Equatable {
        case up
        case down
    }

    private var lowUsage: Set<UsageKey> = []
    private var serviceHealth: [UUID: ServiceHealth] = [:]
    private var batteryLow: Bool?

    mutating func usageEvents(
        providers: [ProviderUsage], remainingThreshold: Int, enabled: Bool
    ) -> [DockNotificationEvent] {
        var next = lowUsage
        var windowsByKey: [UsageKey: (UsageProviderID, UsageWindow)] = [:]

        for provider in providers where provider.freshness == .live {
            next = Set(next.filter { $0.provider != provider.id })
            for window in provider.windows {
                let key = UsageKey(
                    provider: provider.id,
                    windowID: window.id,
                    resetEpoch: Int(window.resetsAt?.timeIntervalSince1970 ?? 0))
                windowsByKey[key] = (provider.id, window)
                if window.remainingPercent <= Double(remainingThreshold) { next.insert(key) }
            }
        }

        let entered = next.subtracting(lowUsage)
        lowUsage = next
        guard enabled else { return [] }

        return entered.sorted(by: Self.usageKeyOrder).compactMap { key in
            guard let (provider, window) = windowsByKey[key] else { return nil }
            let remaining = Int(window.remainingPercent.rounded())
            var body = "\(window.label) has \(remaining)% remaining."
            if let resetsAt = window.resetsAt {
                body += " Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))."
            }
            return DockNotificationEvent(
                identifier: "dockdeck.usage.\(provider.rawValue).\(key.windowID).\(key.resetEpoch)",
                title: "\(provider.title) quota is low",
                body: body)
        }
    }

    mutating func serviceEvents(
        items: [ServiceMonitorItem],
        failuresEnabled: Bool,
        recoveriesEnabled: Bool
    ) -> [DockNotificationEvent] {
        let currentIDs = Set(items.map(\.id))
        serviceHealth = serviceHealth.filter { currentIDs.contains($0.key) }
        var events: [DockNotificationEvent] = []

        for item in items {
            switch item.state {
            case .idle, .checking:
                continue
            case .up:
                if serviceHealth[item.id] == .down, recoveriesEnabled {
                    events.append(
                        DockNotificationEvent(
                            identifier: "dockdeck.service.recovered.\(item.id.uuidString)",
                            title: "\(item.endpoint.displayName) recovered",
                            body: item.state.detail))
                }
                serviceHealth[item.id] = .up
            case .down:
                if serviceHealth[item.id] != .down, failuresEnabled {
                    events.append(
                        DockNotificationEvent(
                            identifier: "dockdeck.service.down.\(item.id.uuidString)",
                            title: "\(item.endpoint.displayName) is unavailable",
                            body: item.state.detail))
                }
                serviceHealth[item.id] = .down
            }
        }
        return events
    }

    mutating func batteryEvents(
        snapshot: BatterySnapshot?, remainingThreshold: Int, enabled: Bool
    ) -> [DockNotificationEvent] {
        guard let snapshot else { return [] }
        let isLow = snapshot.state == .discharging
            && snapshot.percent <= Double(remainingThreshold)
        let entered = isLow && batteryLow != true
        batteryLow = isLow
        guard enabled, entered else { return [] }
        return [
            DockNotificationEvent(
                identifier: "dockdeck.battery.low",
                title: "Battery is low",
                body: "\(Int(snapshot.percent.rounded()))% remaining. Connect power.")
        ]
    }

    private static func usageKeyOrder(_ lhs: UsageKey, _ rhs: UsageKey) -> Bool {
        if lhs.provider.rawValue != rhs.provider.rawValue {
            return lhs.provider.rawValue < rhs.provider.rawValue
        }
        if lhs.windowID != rhs.windowID { return lhs.windowID < rhs.windowID }
        return lhs.resetEpoch < rhs.resetEpoch
    }
}
