import SwiftUI

struct NetworkPanelView: View {
    @Environment(\.compactReadable) private var readable
    @ObservedObject var store: NetworkStore
    let theme: Theme

    var body: some View {
        Group {
            if store.interfaceName.isEmpty && store.connection.status == .offline {
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
                networkPlaceholder(text: store.measurementStatus, symbol: "network.slash")
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
                .font(.system(size: CompactReadability.size(7.5, enabled: readable), weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(ByteRateFormatter.string(value))
                .font(.system(size: CompactReadability.size(11, enabled: readable), weight: .bold, design: .monospaced))
                .foregroundStyle(baseColor)
                .lineLimit(1)
                .minimumScaleFactor(readable ? 1 : 0.65)
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
        .font(.system(size: CompactReadability.size(9.5, enabled: readable), weight: .semibold, design: .rounded))
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

struct NetworkModuleDetailView: View {
    @ObservedObject var store: NetworkStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(store.snapshot?.interfaceName ?? (store.interfaceName.isEmpty ? "Primary interface" : store.interfaceName))
                        .font(.title3.bold())
                    Spacer()
                    Text(store.measurementStatus).foregroundStyle(.secondary)
                }
                Text("System route: \(connectionLabel)")
                if store.connection.isConstrained { Label("Low Data Mode", systemImage: "leaf") }
                if store.connection.isExpensive { Text("Metered connection").font(.caption) }
                history("Download", store.downloadHistory, store.snapshot?.downloadBytesPerSecond, .cyan)
                history("Upload", store.uploadHistory, store.snapshot?.uploadBytesPerSecond, .mint)
                if let date = store.observedAt {
                    Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Rates use bytes per second; KB/MB/GB use powers of 1024. History stays in memory for up to 15 minutes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var connectionLabel: String {
        switch store.connection.status {
        case .unknown: "Unknown"
        case .offline: "Offline"
        case .online: store.connection.kind?.title ?? "Online"
        }
    }

    private func history(_ title: String, _ history: MetricHistory, _ value: Double?, _ color: Color) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(ByteRateFormatter.string(value)).monospacedDigit()
            }
            if history.samples.count >= 2 {
                MetricSparkline(samples: history.samples, color: color).frame(height: 32)
            } else {
                Text("Collecting history").font(.caption).foregroundStyle(.secondary)
                    .frame(height: 32)
            }
            HStack {
                if let first = history.samples.first { Text(first.timestamp, style: .time) }
                Spacer()
                Text("Peak \(ByteRateFormatter.string(history.samples.map(\.value).max()))")
                Spacer()
                if let last = history.samples.last { Text(last.timestamp, style: .time) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
