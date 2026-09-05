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
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Format", systemImage: "textformat")
                        .font(.headline)
                }

                GroupBox("Favorite time zones · up to 3") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.values.clock.favorites, id: \.self) { identifier in
                            HStack {
                                Button(ClockTimeZone.title(identifier: identifier)) {
                                    model.setClockTimeZoneIdentifier(identifier)
                                }.buttonStyle(.link)
                                Spacer()
                                Button("Remove") { model.removeClockFavorite(identifier) }
                            }
                        }
                        Button("Save current time zone", action: model.addClockFavorite)
                            .disabled(model.values.clock.favorites.count >= 3
                                || model.values.clock.favorites.contains(model.values.clock.timeZoneIdentifier))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
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
