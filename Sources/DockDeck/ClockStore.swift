import Foundation

enum ClockHourFormat: String, CaseIterable, Codable {
    case system
    case twelveHour
    case twentyFourHour

    var title: String {
        switch self {
        case .system: "System"
        case .twelveHour: "12-hour"
        case .twentyFourHour: "24-hour"
        }
    }
}

enum ClockTimeZone {
    static let systemIdentifier = "system"

    static func resolved(identifier: String) -> TimeZone {
        guard identifier != systemIdentifier, let timeZone = TimeZone(identifier: identifier)
        else { return .autoupdatingCurrent }
        return timeZone
    }

    static func normalized(identifier: String) -> String {
        identifier == systemIdentifier || TimeZone(identifier: identifier) != nil
            ? identifier : systemIdentifier
    }

    static func title(identifier: String) -> String {
        guard identifier != systemIdentifier else { return "System Time Zone" }
        return identifier.replacingOccurrences(of: "_", with: " ")
    }
}

enum ClockTextFormatter {
    static func time(
        _ date: Date, timeZone: TimeZone, format: ClockHourFormat,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        switch format {
        case .system:
            formatter.locale = locale
            formatter.timeStyle = .short
            formatter.dateStyle = .none
        case .twelveHour:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "h:mm a"
        case .twentyFourHour:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
        }
        return formatter.string(from: date)
    }

    static func date(
        _ date: Date, timeZone: TimeZone, locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: date)
    }
}

final class ClockStore: ObservableObject {
    @Published private(set) var now: Date

    private var timer: Timer?

    init(now: Date = Date()) {
        self.now = now
    }

    func start() {
        guard timer == nil else { return }
        now = Date()
        scheduleNextMinute()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNextMinute() {
        timer?.invalidate()
        let seconds = Calendar.current.dateComponents([.second, .nanosecond], from: Date())
        let elapsed = Double(seconds.second ?? 0)
            + Double(seconds.nanosecond ?? 0) / 1_000_000_000
        let delay = max(60 - elapsed, 0.05)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
            self.scheduleNextMinute()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
