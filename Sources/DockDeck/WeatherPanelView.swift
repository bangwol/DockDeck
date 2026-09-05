import SwiftUI

struct WeatherPanelView: View {
    @ObservedObject var store: WeatherStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                weather(snapshot)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func weather(_ snapshot: WeatherSnapshot) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Image(
                    systemName: WeatherCondition.symbolName(
                        code: snapshot.weatherCode, isDay: snapshot.isDay))
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(snapshot.isDay ? Color.orange : Color.cyan)

                Text(temperature(snapshot.temperature, unit: snapshot.temperatureUnit))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(baseColor)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(WeatherCondition.title(code: snapshot.weatherCode))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(baseColor.opacity(0.78))
                    .lineLimit(1)

                if case .failed = store.status {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 5) {
                Text(snapshot.location.name)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(baseColor)
                    .lineLimit(1)

                Circle()
                    .fill(baseColor.opacity(0.35))
                    .frame(width: 2.5, height: 2.5)

                Text(highLow(snapshot))
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(baseColor.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .help(accessibilitySummary(snapshot))
        .accessibilityElement(children: .contain)
    }

    private var placeholder: some View {
        HStack(spacing: 7) {
            if store.status == .loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: placeholderSymbol)
            }
            Text(placeholderText)
                .lineLimit(2)
        }
        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
        .foregroundStyle(baseColor.opacity(0.78))
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }

    private var placeholderText: String {
        switch store.status {
        case .idle: "Choose a city in Settings"
        case .loading: "Loading weather"
        case .ready: "Weather unavailable"
        case .failed(let reason): reason
        }
    }

    private var placeholderSymbol: String {
        if case .failed = store.status { return "exclamationmark.triangle" }
        return "location.magnifyingglass"
    }

    private var baseColor: Color { Color(theme.foregroundColor) }

    private func temperature(_ value: Double, unit: WeatherTemperatureUnit) -> String {
        "\(Int(value.rounded()))\(unit.symbol)"
    }

    private func highLow(_ snapshot: WeatherSnapshot) -> String {
        let high = snapshot.highTemperature.map { "H \(Int($0.rounded()))°" } ?? "H --"
        let low = snapshot.lowTemperature.map { "L \(Int($0.rounded()))°" } ?? "L --"
        return "\(high)  \(low)"
    }

    private func accessibilitySummary(_ snapshot: WeatherSnapshot) -> String {
        var summary = "\(snapshot.location.name), "
            + "\(WeatherCondition.title(code: snapshot.weatherCode)), "
            + "\(Int(snapshot.temperature.rounded())) degrees "
            + snapshot.temperatureUnit.title
            + ", feels like \(Int(snapshot.apparentTemperature.rounded()))"
        if case .failed(let reason) = store.status { summary += ". Last refresh failed: \(reason)" }
        return summary
    }
}

struct WeatherModuleDetailView: View {
    @ObservedObject var store: WeatherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot = store.snapshot {
                    HStack(alignment: .firstTextBaseline) {
                        Text(snapshot.location.name).font(.title3.bold())
                        Spacer()
                        Text(temperature(snapshot.temperature, unit: snapshot.temperatureUnit))
                            .font(.title.bold()).monospacedDigit()
                    }
                    Text("\(WeatherCondition.title(code: snapshot.weatherCode)) · Feels like \(temperature(snapshot.apparentTemperature, unit: snapshot.temperatureUnit))")
                    Text("Next 12 hours · city time").font(.headline)
                    if snapshot.hourly.isEmpty {
                        Text("Hourly forecast unavailable").foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(snapshot.hourly) { hour in
                                    VStack(spacing: 8) {
                                        Text(ClockTextFormatter.time(hour.date,
                                            timeZone: ClockTimeZone.resolved(identifier: snapshot.location.timezone),
                                            format: .system)).font(.caption)
                                        Image(systemName: WeatherCondition.symbolName(
                                            code: hour.weatherCode ?? -1, isDay: hour.isDay))
                                            .font(.title3)
                                            .accessibilityLabel(WeatherCondition.title(code: hour.weatherCode ?? -1))
                                        Text(hour.temperature.map { temperature($0, unit: snapshot.temperatureUnit) } ?? "--")
                                            .font(.headline)
                                        Label(hour.precipitationProbability.map { "\($0)%" } ?? "--", systemImage: "drop")
                                            .font(.caption).accessibilityLabel("Rain probability")
                                            .accessibilityValue(hour.precipitationProbability.map { "\($0)%" } ?? "Unavailable")
                                    }
                                    .padding(10).frame(minWidth: 64)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                    Text("Updated \(snapshot.receivedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Weather data by Open-Meteo", destination: WeatherAPI.attributionURL).font(.caption)
                } else if store.status == .idle {
                    Text("Choose a city in Settings")
                } else if store.status == .loading {
                    ProgressView("Loading weather")
                }
                if case .failed(let reason) = store.status {
                    Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func temperature(_ value: Double, unit: WeatherTemperatureUnit) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + unit.symbol
    }
}
