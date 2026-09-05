import AppKit
import SwiftUI

struct CustomTilePanelView: View {
    @Environment(\.compactReadable) private var readable
    @ObservedObject var store: CustomTileStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                HStack(spacing: 9) {
                    Image(nsImage: symbolImage(snapshot.content.symbolName))
                        .font(.system(size: CompactReadability.size(18, enabled: readable), weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(snapshot.content.title.uppercased())
                                .font(.system(size: CompactReadability.size(10, enabled: readable), weight: .bold, design: .rounded))
                                .foregroundStyle(baseColor.opacity(0.68))
                                .lineLimit(1)
                            if store.isStale {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: CompactReadability.size(10, enabled: readable)))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(snapshot.content.value)
                            .font(.system(size: CompactReadability.size(readable ? 17 : 14, enabled: readable), weight: .bold, design: .rounded))
                            .foregroundStyle(baseColor)
                            .lineLimit(1)
                            .minimumScaleFactor(readable ? 1 : 0.75)
                        if !readable, let detail = snapshot.content.detail {
                            Text(detail)
                                .font(.system(size: CompactReadability.size(10, enabled: readable), weight: .medium, design: .rounded))
                                .foregroundStyle(baseColor.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .help(store.accessibilitySummary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.content.title)
                .accessibilityValue(store.accessibilitySummary)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private var placeholder: some View {
        HStack(spacing: 7) {
            if case .loading = store.status {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "command")
            }
            Text(placeholderText).lineLimit(2)
        }
        .font(.system(size: CompactReadability.size(9.5, enabled: readable), weight: .semibold, design: .rounded))
        .foregroundStyle(baseColor.opacity(0.78))
        .padding(.horizontal, 9)
    }

    private var placeholderText: String {
        switch store.status {
        case .notConfigured: "Configure Custom Tile"
        case .loading: "Running tile command"
        case .ready: "Custom Tile unavailable"
        case .unavailable(let message): message
        }
    }

    private var baseColor: Color { Color(nsColor: theme.foregroundColor) }

    private func symbolImage(_ symbolName: String?) -> NSImage {
        if let image = symbolName.flatMap({
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)
        }) {
            return image
        }
        return NSImage(systemSymbolName: "command", accessibilityDescription: nil) ?? NSImage()
    }

}
