import SwiftUI

struct NetworkPanelView: View {
    @ObservedObject var store: NetworkStore
    let theme: Theme

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                HStack(spacing: 7) {
                    metric(
                        title: "DOWN",
                        symbol: "arrow.down",
                        value: snapshot.downloadBytesPerSecond,
                        color: .cyan)
                    Divider().overlay(baseColor.opacity(0.15))
                    metric(
                        title: "UP",
                        symbol: "arrow.up",
                        value: snapshot.uploadBytesPerSecond,
                        color: .mint)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .help("Primary interface: " + snapshot.interfaceName)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(snapshot))
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "network.slash")
                    Text("No active network")
                }
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(baseColor.opacity(0.78))
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func metric(
        title: String, symbol: String, value: Double?, color: Color
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var baseColor: Color { Color(theme.foregroundColor) }

    private func accessibilityText(_ snapshot: NetworkSnapshot) -> String {
        snapshot.interfaceName + ", download "
            + ByteRateFormatter.string(snapshot.downloadBytesPerSecond)
            + ", upload " + ByteRateFormatter.string(snapshot.uploadBytesPerSecond)
    }
}
