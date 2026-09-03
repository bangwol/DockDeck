import AppKit
import SwiftUI

struct CustomTilePanelView: View {
    @ObservedObject var store: CustomTileStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                HStack(spacing: 9) {
                    Image(nsImage: symbolImage(snapshot.content.symbolName))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.content.title.uppercased())
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundStyle(baseColor.opacity(0.68))
                        Text(snapshot.content.value)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(baseColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let detail = snapshot.content.detail {
                            Text(detail)
                                .font(.system(size: 7.5, weight: .medium, design: .rounded))
                                .foregroundStyle(baseColor.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .help(helpText(snapshot))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.content.title)
                .accessibilityValue(helpText(snapshot))
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
        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
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

    private func helpText(_ snapshot: CustomTileSnapshot) -> String {
        [snapshot.content.title, snapshot.content.value, snapshot.content.detail]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
