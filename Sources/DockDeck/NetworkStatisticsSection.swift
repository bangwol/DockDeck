import SwiftUI

struct NetworkStatisticsSection: View {
    @ObservedObject var store: NetworkStore

    var body: some View {
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
