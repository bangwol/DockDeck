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
        if case .failed(let reason) = store.status { summary += ". Last refresh failed: \(reason)" }
        return summary
    }
}
