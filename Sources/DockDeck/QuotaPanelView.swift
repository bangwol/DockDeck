import Foundation
import SwiftUI

enum UsageResetFormatter {
    static func compactString(
        for resetAt: Date?, now: Date = Date(), calendar: Calendar = .current
    ) -> String {
        guard let resetAt else { return "--" }
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: resetAt)
        guard let month = components.month, let day = components.day,
            let hour = components.hour, let minute = components.minute
        else { return "--" }

        let time = String(format: "%02d:%02d", hour, minute)
        return calendar.isDate(resetAt, inSameDayAs: now)
            ? time
            : "\(month)/\(day) \(time)"
    }

    static func helpText(for window: UsageWindow) -> String {
        let prefix = window.customLabel == "FBL" ? "Fable weekly limit" : window.label
        guard let resetsAt = window.resetsAt else { return "\(prefix) reset time unavailable" }
        return "\(prefix) resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct UsagePanelConfiguration: Equatable {
    let displayMode: UsageDisplayMode
    let fontName: String
    let fontSize: CGFloat
    let textColor: UsageTextColor

    static var current: UsagePanelConfiguration {
        UsagePanelConfiguration(
            displayMode: PanelSettings.usageDisplayMode,
            fontName: PanelSettings.usageFontName ?? TerminalTheme.defaultFontName,
            fontSize: PanelSettings.usageFontSize,
            textColor: PanelSettings.usageTextColor)
    }

    func font(size: CGFloat? = nil, weight: Font.Weight) -> Font {
        let resolvedSize = size ?? fontSize
        if fontName == TerminalTheme.systemFontName {
            return .system(size: resolvedSize, weight: weight, design: .monospaced)
        }
        return .custom(fontName, size: resolvedSize).weight(weight)
    }
}

struct QuotaPanelView: View {
    @ObservedObject var store: UsageStore
    let theme: Theme
    let configuration: UsagePanelConfiguration

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 240
            VStack(spacing: compact ? 2 : 3) {
                ForEach(store.providers) { provider in
                    QuotaRow(
                        provider: provider,
                        theme: theme,
                        configuration: configuration,
                        compact: compact)
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.001))
    }
}

private struct QuotaRow: View {
    let provider: ProviderUsage
    let theme: Theme
    let configuration: UsagePanelConfiguration
    let compact: Bool

    var body: some View {
        let windows = Array(provider.windows.prefix(3))
        let spacing: CGFloat = compact ? 4 : 6
        let providerWidth: CGFloat = compact ? 44 : 54

        HStack(alignment: .center, spacing: spacing) {
            Text(provider.name)
                .font(configuration.font(weight: .bold))
                .foregroundStyle(providerColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: providerWidth, alignment: .leading)
                .help(provider.detail ?? provider.freshness.label ?? provider.name)

            if windows.isEmpty {
                Text(provider.freshness.label ?? "WAITING")
                    .font(
                        configuration.font(
                            size: max(configuration.fontSize - 1, 7), weight: .semibold))
                    .foregroundStyle(providerColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: spacing) {
                    ForEach(windows) { window in
                        UsageMeter(
                            window: window,
                            configuration: configuration,
                            baseColor: baseColor,
                            meterColor: meterColor(for: window),
                            dense: windows.count > 2)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var baseColor: Color {
        Color(configuration.textColor.color(for: theme))
    }

    private var accessibilityLabel: String {
        guard !provider.windows.isEmpty else {
            return "\(provider.name), \(provider.freshness.label ?? "waiting")"
        }
        let description = configuration.displayMode.accessibilityDescription
        let windows = provider.windows.map {
            "\($0.label) \(Int(configuration.displayMode.value(for: $0).rounded())) percent "
                + "\(description), \(UsageResetFormatter.helpText(for: $0))"
        }.joined(separator: ", ")
        return "\(provider.name), \(windows)"
    }

    private var providerColor: Color {
        switch provider.freshness {
        case .live:
            baseColor
        case .loading:
            Color(nsColor: .secondaryLabelColor)
        case .stale, .signIn, .unavailable, .setupRequired:
            .orange
        }
    }

    private func meterColor(for window: UsageWindow) -> Color {
        let remaining = window.remainingPercent
        if remaining < 20 { return .red }
        if remaining <= 50 { return .orange }
        return baseColor
    }
}

private struct UsageMeter: View {
    let window: UsageWindow
    let configuration: UsagePanelConfiguration
    let baseColor: Color
    let meterColor: Color
    let dense: Bool

    var body: some View {
        VStack(spacing: 1) {
            MeterLabel(
                window: window,
                configuration: configuration,
                baseColor: baseColor,
                meterColor: meterColor,
                dense: dense)
            MeterBar(
                value: configuration.displayMode.value(for: window),
                baseColor: baseColor,
                meterColor: meterColor)
            ResetLabel(
                window: window,
                configuration: configuration,
                baseColor: baseColor,
                dense: dense)
        }
    }
}

private struct MeterLabel: View {
    let window: UsageWindow
    let configuration: UsagePanelConfiguration
    let baseColor: Color
    let meterColor: Color
    let dense: Bool

    var body: some View {
        let value = Int(configuration.displayMode.value(for: window).rounded())
        (Text(window.label).foregroundColor(baseColor.opacity(0.72))
            + Text(" \(value)%").foregroundColor(meterColor))
            .font(
                configuration.font(
                    size: max(configuration.fontSize - (dense ? 0.5 : 0), 7),
                    weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .help(
                "\(value)% \(configuration.displayMode.title.lowercased()) · "
                    + UsageResetFormatter.helpText(for: window))
    }
}

private struct ResetLabel: View {
    let window: UsageWindow
    let configuration: UsagePanelConfiguration
    let baseColor: Color
    let dense: Bool

    var body: some View {
        HStack(spacing: 1.5) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: max(fontSize - 1, 5.5), weight: .semibold))
            Text(UsageResetFormatter.compactString(for: window.resetsAt))
                .font(configuration.font(size: fontSize, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(baseColor.opacity(window.resetsAt == nil ? 0.38 : 0.68))
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .help(UsageResetFormatter.helpText(for: window))
    }

    private var fontSize: CGFloat {
        min(max(configuration.fontSize - (dense ? 3.5 : 2.5), 6.5), 8)
    }
}

private struct MeterBar: View {
    let value: Double
    let baseColor: Color
    let meterColor: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(baseColor.opacity(0.14))
                Capsule()
                    .fill(meterColor)
                    .frame(width: proxy.size.width * min(max(value / 100, 0), 1))
            }
        }
        .frame(height: 2.5)
    }
}
