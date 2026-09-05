import SwiftUI

struct FocusTimerPanelView: View {
    @ObservedObject var store: FocusTimerStore
    let theme: Theme

    var body: some View {
        HStack(spacing: 7) {
            Button(action: { store.toggle() }) {
                Image(systemName: store.snapshot.mode == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 25, height: 25)
                    .background(Circle().fill(baseColor.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help(store.snapshot.mode == .running ? "Pause timer" : "Start timer")
            .accessibilityLabel(store.snapshot.mode == .running ? "Pause timer" : "Start timer")

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(store.snapshot.phase.title)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                    Text(store.snapshot.timeLabel)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(baseColor)
                    Spacer(minLength: 0)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(baseColor.opacity(0.14))
                        Capsule()
                            .fill(accentColor)
                            .frame(width: proxy.size.width * store.snapshot.progress)
                    }
                }
                .frame(height: 3)
            }

            Button(action: { store.reset() }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(baseColor.opacity(0.72))
                    .frame(width: 20, height: 24)
            }
            .buttonStyle(.plain)
            .help("Reset current timer")
            .accessibilityLabel("Reset current timer")

            Button(action: { store.skip() }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(baseColor.opacity(0.72))
                    .frame(width: 20, height: 24)
            }
            .buttonStyle(.plain)
            .help("Skip to \(store.snapshot.phase.next.title.lowercased())")
            .accessibilityLabel("Skip to \(store.snapshot.phase.next.title.lowercased())")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .accessibilityElement(children: .contain)
    }

    private var baseColor: Color { Color(theme.foregroundColor) }
    private var accentColor: Color {
        store.snapshot.phase == .focus ? baseColor : .mint
    }
}

struct FocusTimerModuleDetailView: View {
    @ObservedObject var store: FocusTimerStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(store.snapshot.phase.title).font(.headline)
                Text(store.snapshot.timeLabel).font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit().accessibilityLabel("Remaining time").accessibilityValue(store.snapshot.timeLabel)
                ProgressView(value: store.snapshot.progress).accessibilityLabel("Phase progress")
                HStack {
                    Button(store.snapshot.mode == .running ? "Pause" : "Start") { store.toggle() }
                    Button("Reset phase") { store.reset() }
                    Button("Skip phase") { store.skip() }
                }
                Divider()
                HStack {
                    Text("Completed focus periods: \(store.completedFocusCount.formatted())")
                    Spacer()
                    Button("Reset count") { store.clearCompletedCount() }.disabled(store.completedFocusCount == 0)
                }
                Text("Count is retained until reset. Skipped periods are not counted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12).frame(maxWidth: .infinity)
        }
    }
}
