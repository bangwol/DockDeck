import SwiftUI

struct DockerPanelView: View {
    @Environment(\.compactReadable) private var readable
    @ObservedObject var store: DockerStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                HStack(spacing: 3) {
                    metric("RUN", String(snapshot.runningCount), color: .green)
                    if !readable { metric("STOP", String(snapshot.stoppedCount), color: .secondary) }
                    metric("BAD", String(snapshot.unhealthyCount), color: .red)
                    metric("CPU", percent(snapshot.cpuPercent), color: .cyan)
                    metric("RAM", memory(snapshot.memoryBytes), color: .orange)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 6)
                .help(helpText(snapshot))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Docker")
                .accessibilityValue(helpText(snapshot))
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func metric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: CompactReadability.size(6.5, enabled: readable), weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: CompactReadability.size(9.5, enabled: readable), weight: .bold, design: .rounded))
                .foregroundStyle(baseColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(readable ? 1 : 0.58)
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        HStack(spacing: 7) {
            if case .loading = store.status {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "shippingbox")
            }
            Text(placeholderText).lineLimit(2)
        }
        .font(.system(size: CompactReadability.size(9.5, enabled: readable), weight: .semibold, design: .rounded))
        .foregroundStyle(baseColor.opacity(0.78))
        .padding(.horizontal, 9)
    }

    private var placeholderText: String {
        switch store.status {
        case .loading: "Loading Docker"
        case .ready: "Docker unavailable"
        case .unavailable(let message): message
        }
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "--"
    }

    private func memory(_ value: Double?) -> String {
        guard let value else { return "--" }
        if value >= 1_073_741_824 {
            return String(format: "%.1fG", value / 1_073_741_824)
        }
        return "\(Int((value / 1_048_576).rounded()))M"
    }

    private func helpText(_ snapshot: DockerSnapshot) -> String {
        var text = "\(snapshot.runningCount) running, \(snapshot.stoppedCount) stopped, "
            + "\(snapshot.unhealthyCount) unhealthy, CPU \(percent(snapshot.cpuPercent)), "
            + "memory \(memory(snapshot.memoryBytes))"
        if case .unavailable(let message) = store.status {
            text += ", last refresh failed: \(message)"
        }
        return text
    }
}
