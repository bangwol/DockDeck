import SwiftUI

struct ServiceMonitorPanelView: View {
    @ObservedObject var store: ServiceMonitorStore
    let theme: Theme

    var body: some View {
        if store.items.isEmpty {
            Label("Add services in Settings", systemImage: "plus.circle")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(baseColor.opacity(0.78))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.001))
        } else {
            GeometryReader { _ in
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(store.items) { item in
                        ServiceMonitorCell(
                            item: item,
                            history: store.latencyHistory(for: item.id),
                            baseColor: baseColor)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.opacity(0.001))
        }
    }

    private var columns: [GridItem] {
        let count = store.items.count <= 2 ? max(store.items.count, 1) : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: count)
    }

    private var baseColor: Color { Color(theme.foregroundColor) }
}

private struct ServiceMonitorCell: View {
    let item: ServiceMonitorItem
    let history: MetricHistory
    let baseColor: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(item.endpoint.displayName)
                .foregroundStyle(baseColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 1)
            Text(item.state.shortLabel)
                .foregroundStyle(statusColor)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 20, maxHeight: .infinity)
        .background(Capsule().fill(baseColor.opacity(0.09)))
        .overlay(alignment: .bottom) {
            if history.samples.count >= 2 {
                MetricSparkline(samples: history.samples, color: statusColor)
                    .frame(height: 3)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 1)
            }
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.endpoint.displayName)
        .accessibilityValue(item.state.detail)
    }

    private var statusColor: Color {
        switch item.state {
        case .idle, .checking: return Color(nsColor: .secondaryLabelColor)
        case .up: return .green
        case .degraded: return .orange
        case .offline: return Color(nsColor: .secondaryLabelColor)
        case .down: return .red
        }
    }

    private var helpText: String {
        var parts = ["\(item.endpoint.displayName): \(item.state.detail)"]
        if let p50 = history.percentile(0.5), let p95 = history.percentile(0.95) {
            parts.append("latency p50 \(Int(p50.rounded())) ms, p95 \(Int(p95.rounded())) ms")
        }
        return parts.joined(separator: " · ")
    }
}
