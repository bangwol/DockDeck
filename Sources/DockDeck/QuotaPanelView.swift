import SwiftUI

struct QuotaPanelView: View {
    @ObservedObject var store: UsageStore
    let theme: Theme

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 300
            VStack(spacing: 2) {
                ForEach(store.providers) { provider in
                    QuotaRow(provider: provider, theme: theme, compact: compact)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.001))
    }
}

private struct QuotaRow: View {
    let provider: ProviderUsage
    let theme: Theme
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 4 : 7) {
            Text(compact ? provider.shortName : provider.name)
                .font(.system(size: compact ? 10 : 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(theme.foregroundColor))
                .frame(width: compact ? 12 : 46, alignment: .leading)

            ForEach(Array(provider.windows.prefix(2))) { window in
                WindowMeter(window: window, theme: theme, compact: compact)
            }

            Spacer(minLength: 0)

            if let label = provider.freshness.label {
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        provider.freshness == .loading
                            ? Color(nsColor: .secondaryLabelColor) : Color.orange)
            }
        }
        .help(provider.detail ?? provider.freshness.label ?? provider.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let windows = provider.windows.map {
            "\($0.label) \(Int($0.usedPercent.rounded())) percent used"
        }.joined(separator: ", ")
        return "\(provider.name), \(windows)"
    }
}

private struct WindowMeter: View {
    let window: UsageWindow
    let theme: Theme
    let compact: Bool

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Text(window.label)
                    .foregroundStyle(Color(theme.foregroundColor).opacity(0.7))
                Text("\(Int(window.usedPercent.rounded()))%")
                    .foregroundStyle(meterColor)
            }
            .font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(theme.foregroundColor).opacity(0.14))
                    Capsule()
                        .fill(meterColor)
                        .frame(
                            width: proxy.size.width
                                * min(max(window.usedPercent / 100, 0), 1))
                }
            }
            .frame(height: 2)
        }
        .frame(width: compact ? 48 : 64)
        .help(resetHelp)
    }

    private var meterColor: Color {
        let remaining = 100 - window.usedPercent
        if remaining < 20 { return .red }
        if remaining <= 50 { return .orange }
        return Color(theme.foregroundColor)
    }

    private var resetHelp: String {
        guard let resetsAt = window.resetsAt else { return "Reset time unavailable" }
        return "Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
