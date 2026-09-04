import SwiftUI

struct MusicSettingsView: View {
    @ObservedObject var store: MusicStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: statusSymbol)
                            .font(.system(size: 20))
                            .foregroundStyle(statusColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(statusTitle).fontWeight(.medium)
                            Text(statusDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        connectionAction
                    }
                    .padding(.vertical, 6)
                } label: {
                    Label("Music Connection", systemImage: "lock.shield")
                        .font(.headline)
                }

                GroupBox {
                    HStack(spacing: 14) {
                        Button(action: { store.send(.previous) }) {
                            Label("Previous", systemImage: "backward.end.fill")
                        }
                        Button(action: { store.send(.playPause) }) {
                            Label(playPauseTitle, systemImage: playPauseSymbol)
                        }
                        .buttonStyle(.borderedProminent)
                        Button(action: { store.send(.next) }) {
                            Label("Next", systemImage: "forward.end.fill")
                        }
                        Spacer()
                        Button("Open Music", action: store.openMusic)
                    }
                    .disabled(!store.canControl)
                    .padding(.vertical, 6)
                } label: {
                    Label("Playback", systemImage: "play.circle")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Current song, artist, album, and progress", systemImage: "music.note")
                        Label("Previous, play or pause, and next", systemImage: "playpause")
                        Label("5 seconds visible · 30 seconds in background", systemImage: "timer")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("Displayed Data", systemImage: "waveform")
                        .font(.headline)
                }

                Text(
                    "DockDeck controls only the macOS Music app through Apple Events. "
                        + "Connect requests Automation access only after you press the button. "
                        + "Track details stay in memory and are never logged or sent over the network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onAppear { store.refresh() }
    }

    @ViewBuilder private var connectionAction: some View {
        switch store.status {
        case .checking:
            ProgressView().controlSize(.small)
        case .notRunning:
            Button("Open & Connect", action: store.requestAccess)
        case .permissionRequired:
            Button("Connect", action: store.requestAccess)
        case .permissionDenied:
            Button("Check Again", action: store.refresh)
        case .ready:
            Button(action: store.refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        case .unavailable:
            Button("Check Again", action: store.refresh)
        }
    }

    private var statusTitle: String {
        switch store.status {
        case .checking: "Checking Music access"
        case .notRunning: "Music is not running"
        case .permissionRequired: "Music access has not been requested"
        case .permissionDenied: "Music access denied"
        case .ready: "Music connected"
        case .unavailable: "Music automation unavailable"
        }
    }

    private var statusDetail: String {
        switch store.status {
        case .checking: "Waiting for the local Music app."
        case .notRunning: "The button opens Music without bringing it to the front."
        case .permissionRequired: "Access is requested only after you press Connect."
        case .permissionDenied:
            "Enable DockDeck in System Settings → Privacy & Security → Automation."
        case .ready: "DockDeck can read playback state and send transport controls."
        case .unavailable:
            "Install DockDeck.app and verify its Automation permission."
        }
    }

    private var statusSymbol: String {
        switch store.status {
        case .checking: "ellipsis.circle"
        case .notRunning: "power"
        case .permissionRequired: "lock"
        case .permissionDenied: "lock.slash"
        case .ready: "checkmark.circle.fill"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .ready: .green
        case .permissionDenied, .unavailable: .orange
        default: .secondary
        }
    }

    private var playPauseTitle: String {
        store.snapshot?.state.isPlaying == true ? "Pause" : "Play"
    }

    private var playPauseSymbol: String {
        store.snapshot?.state.isPlaying == true ? "pause.fill" : "play.fill"
    }
}
