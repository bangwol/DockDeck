import SwiftUI

struct QuotaPanelView: View {
    @ObservedObject var store: UsageStore
    let theme: Theme

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 240
            VStack(spacing: compact ? 1 : 2) {
                HStack {
                    Spacer(minLength: 0)
                    Text("REMAINING")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(theme.foregroundColor).opacity(0.55))
                }
                .frame(height: 8)

                ForEach(store.providers) { provider in
                    QuotaRow(provider: provider, theme: theme, compact: compact)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.top, 3)
            .padding(.bottom, 5)
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
        HStack(alignment: .firstTextBaseline, spacing: compact ? 3 : 6) {
            Text(provider.name)
                .font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
                .foregroundStyle(providerColor)
                .frame(width: compact ? 42 : 52, alignment: .leading)

            if provider.windows.isEmpty {
                let label = provider.freshness.label ?? "WAITING"
                Text(label)
                    .font(.system(size: compact ? 8 : 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(providerColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let dense = provider.windows.count > 2
                ForEach(Array(provider.windows.prefix(3))) { window in
                    WindowMeter(
                        window: window, theme: theme, compact: compact, dense: dense)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .help(provider.detail ?? provider.freshness.label ?? provider.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard !provider.windows.isEmpty else {
            return "\(provider.name), \(provider.freshness.label ?? "waiting")"
        }
        let windows = provider.windows.map {
            "\($0.label) \(Int($0.remainingPercent.rounded())) percent remaining"
        }.joined(separator: ", ")
        return "\(provider.name), \(windows)"
    }

    private var providerColor: Color {
        switch provider.freshness {
        case .live:
            Color(theme.foregroundColor)
        case .loading:
            Color(nsColor: .secondaryLabelColor)
        case .stale, .signIn, .unavailable, .setupClaude:
            .orange
        }
    }
}

private struct WindowMeter: View {
    let window: UsageWindow
    let theme: Theme
    let compact: Bool
    let dense: Bool

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: dense ? 1 : 2) {
                Text(window.label)
                    .foregroundStyle(Color(theme.foregroundColor).opacity(0.7))
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .foregroundStyle(meterColor)
            }
            .font(
                .system(
                    size: dense ? 7 : (compact ? 8 : 10),
                    weight: .medium, design: .monospaced)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(theme.foregroundColor).opacity(0.14))
                    Capsule()
                        .fill(meterColor)
                        .frame(
                            width: proxy.size.width
                                * min(max(window.remainingPercent / 100, 0), 1))
                }
            }
            .frame(height: compact ? 2 : 3)
        }
        .help("\(Int(window.remainingPercent.rounded()))% remaining · \(resetHelp)")
    }

    private var meterColor: Color {
        let remaining = window.remainingPercent
        if remaining < 20 { return .red }
        if remaining <= 50 { return .orange }
        return Color(theme.foregroundColor)
    }

    private var resetHelp: String {
        let prefix = window.customLabel == "FBL" ? "Fable weekly limit" : window.label
        guard let resetsAt = window.resetsAt else { return "\(prefix) reset time unavailable" }
        return "\(prefix) resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
