import SwiftUI

struct BatteryPanelView: View {
    @ObservedObject var store: BatteryStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                battery(snapshot)
            } else {
                noBattery
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func battery(_ snapshot: BatterySnapshot) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName(snapshot))
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(statusColor(snapshot))
                .frame(width: 28)

            Text(String(Int(snapshot.percent.rounded())) + "%")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(baseColor)
                .monospacedDigit()
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(snapshot.state.title)
                        .foregroundStyle(baseColor)
                    Spacer(minLength: 0)
                    Text(estimateText(snapshot))
                        .foregroundStyle(baseColor.opacity(0.7))
                }
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(baseColor.opacity(0.14))
                        Capsule()
                            .fill(statusColor(snapshot))
                            .frame(
                                width: proxy.size.width
                                    * CGFloat(min(max(snapshot.percent / 100, 0), 1)))
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(snapshot))
    }

    private var noBattery: some View {
        HStack(spacing: 7) {
            Image(systemName: "battery.0percent")
            Text("No internal battery")
        }
        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
        .foregroundStyle(baseColor.opacity(0.78))
        .accessibilityElement(children: .combine)
    }

    private var baseColor: Color { Color(theme.foregroundColor) }

    private func statusColor(_ snapshot: BatterySnapshot) -> Color {
        if snapshot.state == .charging { return .green }
        if snapshot.percent <= 20 { return .red }
        if snapshot.percent <= 35 { return .orange }
        return baseColor
    }

    private func symbolName(_ snapshot: BatterySnapshot) -> String {
        switch snapshot.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func estimateText(_ snapshot: BatterySnapshot) -> String {
        guard let minutes = snapshot.minutesRemaining else {
            switch snapshot.state {
            case .charged: return "Full"
            case .connected: return "AC"
            default: return "Calculating"
            }
        }
        let time = duration(minutes)
        return snapshot.state == .charging ? time + " to full" : time + " left"
    }

    private func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return String(remainder) + "m" }
        if remainder == 0 { return String(hours) + "h" }
        return String(hours) + "h " + String(remainder) + "m"
    }

    private func accessibilityText(_ snapshot: BatterySnapshot) -> String {
        String(Int(snapshot.percent.rounded())) + " percent, "
            + snapshot.state.title + ", " + estimateText(snapshot)
    }
}
