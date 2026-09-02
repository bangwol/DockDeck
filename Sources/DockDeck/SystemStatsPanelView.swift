import SwiftUI

struct SystemStatsPanelView: View {
    @ObservedObject var store: SystemStatsStore
    let theme: Theme

    var body: some View {
        HStack(spacing: store.selectedMetrics.count >= 4 ? 4 : 7) {
            ForEach(store.selectedMetrics) { metric($0) }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    @ViewBuilder private func metric(_ metric: SystemStatsMetric) -> some View {
        switch metric {
        case .cpu:
            percentMetric(metric, value: store.snapshot.cpuPercent)
        case .memory:
            percentMetric(metric, value: store.snapshot.memoryPercent)
        case .disk:
            percentMetric(metric, value: store.snapshot.diskPercent)
        case .network:
            networkMetric
        case .thermal:
            thermalMetric
        }
    }

    private func percentMetric(_ metric: SystemStatsMetric, value: Double?) -> some View {
        let color = percentColor(value)
        return VStack(spacing: 3) {
            metricHeader(metric)
            Text(value.map { "\(Int($0.rounded()))%" } ?? "--")
                .font(.system(size: valueFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            indicatorBar(value: (value ?? 0) / 100, color: color)
        }
        .frame(maxWidth: .infinity)
        .help(value.map { "\(metric.title) \(Int($0.rounded())) percent used" }
            ?? "\(metric.title) unavailable")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(value.map { "\(Int($0.rounded())) percent used" } ?? "Unavailable")
    }

    private var networkMetric: some View {
        VStack(spacing: 2) {
            metricHeader(.network)
            rateRow(
                symbol: "arrow.down",
                value: store.snapshot.downloadBytesPerSecond,
                color: .cyan)
            rateRow(
                symbol: "arrow.up",
                value: store.snapshot.uploadBytesPerSecond,
                color: .mint)
        }
        .frame(maxWidth: .infinity)
        .help(
            "Download \(ByteRateFormatter.string(store.snapshot.downloadBytesPerSecond)), "
                + "upload \(ByteRateFormatter.string(store.snapshot.uploadBytesPerSecond))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network I/O")
        .accessibilityValue(
            "Download \(ByteRateFormatter.string(store.snapshot.downloadBytesPerSecond)), "
                + "upload \(ByteRateFormatter.string(store.snapshot.uploadBytesPerSecond))")
    }

    private var thermalMetric: some View {
        let pressure = store.snapshot.thermalPressure
        let temperature = store.snapshot.temperatureCelsius
        let color = thermalColor(pressure)
        return VStack(spacing: 3) {
            metricHeader(.thermal)
            Text(temperature.map { "\(Int($0.rounded()))°" } ?? "--°")
                .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            indicatorBar(value: pressure?.level ?? 0, color: color)
        }
        .frame(maxWidth: .infinity)
        .help(
            temperature.map {
                "Hottest available CPU core: \(Int($0.rounded())) degrees Celsius"
            } ?? "Numeric temperature source unavailable")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temperature")
        .accessibilityValue(
            temperature.map {
                "\(Int($0.rounded())) degrees Celsius, thermal state "
                    + (pressure?.accessibilityTitle ?? "unavailable")
            } ?? "Unavailable")
    }

    private func metricHeader(_ metric: SystemStatsMetric) -> some View {
        HStack(spacing: 2) {
            Image(systemName: metric.symbolName)
            Text(metric.compactTitle)
        }
        .font(.system(size: 7.5, weight: .bold, design: .rounded))
        .foregroundStyle(baseColor.opacity(0.72))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func rateRow(symbol: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(color)
            Text(ByteRateFormatter.compactString(value))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(baseColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func indicatorBar(value: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(baseColor.opacity(0.14))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 3)
    }

    private var valueFontSize: CGFloat {
        store.selectedMetrics.count >= 4 ? 9.5 : 10.5
    }

    private var baseColor: Color { Color(theme.foregroundColor) }

    private func percentColor(_ value: Double?) -> Color {
        guard let value else { return Color(nsColor: .secondaryLabelColor) }
        if value >= 90 { return .red }
        if value >= 75 { return .orange }
        return baseColor
    }

    private func thermalColor(_ pressure: SystemThermalPressure?) -> Color {
        switch pressure {
        case .nominal: .mint
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        case nil: Color(nsColor: .secondaryLabelColor)
        }
    }
}
