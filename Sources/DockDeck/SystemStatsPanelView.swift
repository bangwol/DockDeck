import SwiftUI

struct SystemStatsPanelView: View {
    @ObservedObject var store: SystemStatsStore
    let theme: Theme

    var body: some View {
        HStack(spacing: 7) {
            metric(title: "CPU", value: store.snapshot.cpuPercent)
            metric(title: "MEM", value: store.snapshot.memoryPercent)
            metric(title: "DISK", value: store.snapshot.diskPercent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func metric(title: String, value: Double?) -> some View {
        let color = metricColor(value)
        return VStack(spacing: 4) {
            HStack(spacing: 3) {
                Text(title)
                    .foregroundStyle(baseColor.opacity(0.72))
                Spacer(minLength: 0)
                Text(value.map { "\(Int($0.rounded()))%" } ?? "--")
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(baseColor.opacity(0.14))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat(min(max((value ?? 0) / 100, 0), 1)))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .help(value.map { "\(title) \(Int($0.rounded())) percent used" } ?? "\(title) unavailable")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\(Int($0.rounded())) percent used" } ?? "Unavailable")
    }

    private var baseColor: Color { Color(theme.foregroundColor) }

    private func metricColor(_ value: Double?) -> Color {
        guard let value else { return Color(nsColor: .secondaryLabelColor) }
        if value >= 90 { return .red }
        if value >= 75 { return .orange }
        return baseColor
    }
}
