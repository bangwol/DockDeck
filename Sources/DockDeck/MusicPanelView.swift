import SwiftUI

struct MusicPanelView: View {
    @ObservedObject var store: MusicStore
    let theme: Theme

    var body: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accentColor)
                    Text(primaryText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(baseColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Text(secondaryText)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(baseColor.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                progressBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 1) {
                controlButton(
                    command: .previous, symbol: "backward.end.fill",
                    label: "Previous track", prominent: false)
                controlButton(
                    command: .playPause, symbol: playPauseSymbol,
                    label: playPauseLabel, prominent: true)
                controlButton(
                    command: .next, symbol: "forward.end.fill",
                    label: "Next track", prominent: false)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .help(helpText)
        .accessibilityElement(children: .contain)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(baseColor.opacity(0.13))
                Capsule()
                    .fill(accentColor)
                    .frame(
                        width: proxy.size.width
                            * CGFloat(store.snapshot?.track?.progress ?? 0))
            }
        }
        .frame(height: 3)
        .opacity(store.snapshot?.track?.progress == nil ? 0.45 : 1)
        .accessibilityHidden(true)
    }

    private func controlButton(
        command: MusicCommand, symbol: String, label: String, prominent: Bool
    ) -> some View {
        Button(action: { store.send(command) }) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 10 : 8, weight: .bold))
                .foregroundStyle(prominent ? accentColor : baseColor.opacity(0.76))
                .frame(width: prominent ? 25 : 20, height: 25)
                .background {
                    if prominent { Circle().fill(baseColor.opacity(0.1)) }
                }
        }
        .buttonStyle(.plain)
        .disabled(!store.canControl)
        .help(label)
        .accessibilityLabel(label)
    }

    private var primaryText: String {
        if let track = store.snapshot?.track { return track.title }
        return switch store.status {
        case .checking: "Checking Music…"
        case .notRunning: "Music is not running"
        case .permissionRequired: "Connect Music"
        case .permissionDenied: "Music access denied"
        case .ready: "Nothing playing"
        case .unavailable: "Music unavailable"
        }
    }

    private var secondaryText: String {
        if let snapshot = store.snapshot, let track = snapshot.track {
            return track.artist + " · " + snapshot.state.title
        }
        return switch store.status {
        case .checking: "Waiting for status"
        case .notRunning: "Open it from Settings"
        case .permissionRequired: "Allow Automation in Settings"
        case .permissionDenied: "Check macOS Automation"
        case .ready: store.snapshot?.state.title ?? "Stopped"
        case .unavailable: "Check connection in Settings"
        }
    }

    private var playPauseSymbol: String {
        store.snapshot?.state == .playing ? "pause.fill" : "play.fill"
    }

    private var playPauseLabel: String {
        store.snapshot?.state == .playing ? "Pause" : "Play"
    }

    private var helpText: String {
        if let track = store.snapshot?.track {
            let album = track.album.map { " · \($0)" } ?? ""
            return "\(track.title) · \(track.artist)\(album)"
        }
        return secondaryText
    }

    private var baseColor: Color { Color(theme.foregroundColor) }
    private var accentColor: Color { .pink }
}
