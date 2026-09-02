import SwiftUI

struct WeatherSettingsView: View {
    @ObservedObject var model: SettingsPanelModel
    @StateObject private var searchStore = WeatherLocationSearchStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                locationSection
                displaySection
                refreshSection

                Text(
                    "DockDeck does not use IP geolocation or request Location permission. "
                        + "Search text and the selected coordinates are sent to Open-Meteo only "
                        + "when you search or while the enabled Weather module refreshes. The "
                        + "selected city is stored in local preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onDisappear { searchStore.cancel() }
    }

    private var locationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let location = model.values.weather.location {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name).fontWeight(.medium)
                            if !location.detail.isEmpty {
                                Text(location.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Clear") { model.setWeatherLocation(nil) }
                    }
                    .padding(.vertical, 3)
                    Divider()
                }

                HStack(spacing: 8) {
                    TextField("Search city or postal code", text: $searchStore.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(searchStore.search)
                    Button(action: searchStore.search) {
                        if searchStore.status == .searching {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(searchStore.status == .searching)
                }

                switch searchStore.status {
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                default:
                    EmptyView()
                }

                ForEach(searchStore.results) { location in
                    Button {
                        model.setWeatherLocation(location)
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName: model.values.weather.location?.id == location.id
                                    ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    model.values.weather.location?.id == location.id
                                        ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location.name).foregroundStyle(.primary)
                                if !location.detail.isEmpty {
                                    Text(location.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.primary.opacity(0.045)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select \(location.name), \(location.detail)")
                }

                HStack {
                    Link("Weather data by Open-Meteo.com", destination: WeatherAPI.attributionURL)
                    Text("·")
                    Link("CC BY 4.0", destination: WeatherAPI.licenseURL)
                    Spacer()
                }
                .font(.caption)
            }
            .padding(.top, 4)
        } label: {
            Label("Location", systemImage: "location.magnifyingglass")
                .font(.headline)
        }
    }

    private var displaySection: some View {
        GroupBox {
            SettingsPickerRow(title: "Temperature") {
                Picker(
                    "Temperature unit",
                    selection: Binding(
                        get: { model.values.weather.temperatureUnit },
                        set: model.setWeatherTemperatureUnit)
                ) {
                    ForEach(WeatherTemperatureUnit.allCases, id: \.self) { unit in
                        Text("\(unit.title) (\(unit.symbol))").tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .padding(.top, 4)
        } label: {
            Label("Display", systemImage: "thermometer.medium")
                .font(.headline)
        }
    }

    private var refreshSection: some View {
        GroupBox {
            SettingsPickerRow(title: "Refresh") {
                Picker(
                    "Weather refresh interval",
                    selection: Binding(
                        get: { model.values.weather.refreshInterval },
                        set: model.setWeatherRefreshInterval)
                ) {
                    ForEach(PanelSettings.weatherRefreshIntervals, id: \.self) {
                        Text("\(Int($0 / 60)) minutes").tag($0)
                    }
                }
                .labelsHidden()
            }
            .padding(.top, 4)
        } label: {
            Label("Polling", systemImage: "timer")
                .font(.headline)
        }
    }
}
