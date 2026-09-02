import SwiftUI

struct ClockPanelView: View {
    @ObservedObject var store: ClockStore
    let theme: Theme
    let timeZoneIdentifier: String
    let hourFormat: ClockHourFormat

    var body: some View {
        let timeZone = ClockTimeZone.resolved(identifier: timeZoneIdentifier)
        HStack(spacing: 9) {
            Image(systemName: "clock.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.cyan)

            Text(ClockTextFormatter.time(store.now, timeZone: timeZone, format: hourFormat))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(baseColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            VStack(alignment: .leading, spacing: 1) {
                Text(ClockTextFormatter.date(store.now, timeZone: timeZone))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(baseColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(timeZoneLabel(timeZone))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(baseColor.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ClockTextFormatter.date(store.now, timeZone: timeZone) + ", "
                + ClockTextFormatter.time(
                    store.now, timeZone: timeZone, format: hourFormat) + ", "
                + timeZoneLabel(timeZone))
    }

    private var baseColor: Color { Color(theme.foregroundColor) }

    private func timeZoneLabel(_ timeZone: TimeZone) -> String {
        let abbreviation = timeZone.abbreviation(for: store.now) ?? timeZone.identifier
        guard timeZoneIdentifier != ClockTimeZone.systemIdentifier else {
            return "Local · " + abbreviation
        }
        let city = timeZone.identifier.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "_", with: " ") ?? timeZone.identifier
        return city + " · " + abbreviation
    }
}
