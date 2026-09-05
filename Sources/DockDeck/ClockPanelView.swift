import SwiftUI

struct ClockPanelView: View {
    @Environment(\.compactReadable) private var readable
    @ObservedObject var store: ClockStore
    let theme: Theme
    let timeZoneIdentifier: String
    let hourFormat: ClockHourFormat

    var body: some View {
        let timeZone = ClockTimeZone.resolved(identifier: timeZoneIdentifier)
        HStack(spacing: 9) {
            Image(systemName: "clock.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: CompactReadability.size(21, enabled: readable), weight: .semibold))
                .foregroundStyle(Color.cyan)

            Text(ClockTextFormatter.time(store.now, timeZone: timeZone, format: hourFormat))
                .font(.system(size: CompactReadability.size(20, enabled: readable), weight: .bold, design: .rounded))
                .foregroundStyle(baseColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(readable ? 1 : 0.72)

            VStack(alignment: .leading, spacing: 1) {
                Text(ClockTextFormatter.date(store.now, timeZone: timeZone))
                    .font(.system(size: CompactReadability.size(9.5, enabled: readable), weight: .semibold, design: .rounded))
                    .foregroundStyle(baseColor)
                    .lineLimit(1)
                    .minimumScaleFactor(readable ? 1 : 0.8)
                Text(timeZoneLabel(timeZone))
                    .font(.system(size: CompactReadability.size(8, enabled: readable), weight: .medium, design: .rounded))
                    .foregroundStyle(baseColor.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(readable ? 1 : 0.8)
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

struct ClockModuleDetailView: View {
    @ObservedObject var store: ClockStore
    let timeZoneIdentifier: String
    let hourFormat: ClockHourFormat
    let favorites: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                clock(timeZoneIdentifier)
                ForEach(ClockTimeZone.favorites(favorites).filter { $0 != timeZoneIdentifier }, id: \.self) { identifier in
                    clock(identifier)
                }
                if favorites.isEmpty {
                    Text("Save up to three favorite time zones in Settings.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func clock(_ identifier: String) -> some View {
        let timeZone = ClockTimeZone.resolved(identifier: identifier)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ClockTimeZone.title(identifier: identifier, at: store.now)).font(.headline)
                Spacer()
                Text(ClockTextFormatter.time(store.now, timeZone: timeZone, format: hourFormat))
                    .font(.title2).monospacedDigit()
            }
            HStack {
                Text(ClockTextFormatter.date(store.now, timeZone: timeZone))
                Spacer()
                Text("Local difference: \(ClockTimeZone.differenceLabel(identifier: identifier, at: store.now))")
            }.font(.callout)
            Text(timeZone.isDaylightSavingTime(for: store.now) ? "Daylight saving time" : "Standard time")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
