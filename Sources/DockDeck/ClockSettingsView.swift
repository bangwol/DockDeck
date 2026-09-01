import SwiftUI

struct ClockSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    private let timeZoneIdentifiers = [ClockTimeZone.systemIdentifier]
        + TimeZone.knownTimeZoneIdentifiers

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    SettingsPickerRow(title: "Time Zone") {
                        Picker(
                            "Clock time zone",
                            selection: Binding(
                                get: { model.values.clock.timeZoneIdentifier },
                                set: model.setClockTimeZoneIdentifier)
                        ) {
                            ForEach(timeZoneIdentifiers, id: \.self) { identifier in
                                Text(ClockTimeZone.title(identifier: identifier))
                                    .tag(identifier)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Location", systemImage: "globe")
                        .font(.headline)
                }

                GroupBox {
                    SettingsPickerRow(title: "Time") {
                        Picker(
                            "Clock hour format",
                            selection: Binding(
                                get: { model.values.clock.hourFormat },
                                set: model.setClockHourFormat)
                        ) {
                            ForEach(ClockHourFormat.allCases, id: \.self) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Format", systemImage: "textformat")
                        .font(.headline)
                }

                Text(
                    "Time is calculated locally with the macOS time-zone database. "
                        + "The clock updates once per minute and stops while disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
