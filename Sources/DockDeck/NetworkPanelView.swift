import SwiftUI

struct NetworkPanelView: View {
    @ObservedObject var store: NetworkStore
    let theme: Theme

    var body: some View {
        Group {
            if store.connection.status == .offline {
                networkPlaceholder(text: "Network offline", symbol: "network.slash")
            } else if let snapshot = store.snapshot {
                HStack(spacing: 7) {
                    metric(
                        title: downloadTitle,
                        symbol: "arrow.down",
                        value: snapshot.downloadBytesPerSecond,
                        history: store.downloadHistory,
                        color: .cyan)
                    Divider().overlay(baseColor.opacity(0.15))
                    metric(
                        title: "UP",
                        symbol: "arrow.up",
                        value: snapshot.uploadBytesPerSecond,
                        history: store.uploadHistory,
                        color: .mint)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .help(helpText(snapshot))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(snapshot))
            } else {
                networkPlaceholder(text: "No active network", symbol: "network.slash")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func metric(
        title: String, symbol: String, value: Double?, history: MetricHistory, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(ByteRateFormatter.string(value))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(baseColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if history.samples.count >= 2 {
                MetricSparkline(samples: history.samples, color: color)
                    .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var baseColor: Color { Color(theme.foregroundColor) }

    private var downloadTitle: String {
        guard let kind = store.connection.kind else { return "DOWN" }
        return "DOWN · \(kind.title.uppercased())"
    }

    private func networkPlaceholder(text: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
        .foregroundStyle(baseColor.opacity(0.78))
        .accessibilityElement(children: .combine)
    }

    private func helpText(_ snapshot: NetworkSnapshot) -> String {
        var parts = [
            "\(store.connection.kind?.title ?? "Primary interface") via \(snapshot.interfaceName)"
        ]
        if store.connection.isConstrained { parts.append("Low Data Mode") }
        if store.connection.isExpensive { parts.append("metered connection") }
        parts.append("download \(ByteRateFormatter.string(snapshot.downloadBytesPerSecond))")
        parts.append("upload \(ByteRateFormatter.string(snapshot.uploadBytesPerSecond))")
        return parts.joined(separator: " · ")
    }

    private func accessibilityText(_ snapshot: NetworkSnapshot) -> String {
        (store.connection.kind?.title ?? "Network") + " on " + snapshot.interfaceName
            + ", download "
            + ByteRateFormatter.string(snapshot.downloadBytesPerSecond)
            + ", upload " + ByteRateFormatter.string(snapshot.uploadBytesPerSecond)
    }
}
