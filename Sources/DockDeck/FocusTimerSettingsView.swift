import SwiftUI

struct FocusTimerSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 14) {
                        SettingsPickerRow(title: "Focus") {
                            Picker(
                                "Focus duration",
                                selection: Binding(
                                    get: { model.values.focusTimer.focusMinutes },
                                    set: model.setFocusTimerFocusMinutes)
                            ) {
                                ForEach(FocusTimerSettings.focusDurations, id: \.self) {
                                    Text("\($0) minutes").tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                        SettingsPickerRow(title: "Break") {
                            Picker(
                                "Break duration",
                                selection: Binding(
                                    get: { model.values.focusTimer.breakMinutes },
                                    set: model.setFocusTimerBreakMinutes)
                            ) {
                                ForEach(FocusTimerSettings.breakDurations, id: \.self) {
                                    Text("\($0) minutes").tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Durations", systemImage: "timer")
                        .font(.headline)
                }

                Toggle("Automatically start the next focus or break", isOn: Binding(
                    get: { model.values.focusTimer.automaticallyAdvances },
                    set: model.setFocusTimerAutomaticallyAdvances))
                Text("Off by default. After sleep or restart, only one completion is counted and the next phase starts from now.")
                    .font(.caption).foregroundStyle(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Play or pause from the compact panel", systemImage: "playpause")
                        Label("Reset the current phase with ↶", systemImage: "arrow.counterclockwise")
                        Label("Skip between focus and break with ⇥", systemImage: "forward.end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("Controls", systemImage: "slider.horizontal.3")
                        .font(.headline)
                }

                Text(
                    "A running countdown continues while another module is visible. DockDeck "
                        + "stores the phase, remaining time, deadline, and completed focus count when the timer "
                        + "changes; it does not write preferences every second. Completion alerts "
                        + "follow the global Notifications setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
