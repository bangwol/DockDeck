import SwiftUI

struct ScheduleSettingsView: View {
    @ObservedObject var model: SettingsPanelModel
    @ObservedObject var store: ScheduleStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                permissionSection
                if store.authorization.canRead {
                    calendarsSection
                    displaySection
                    refreshSection
                }

                Text(
                    "DockDeck reads only event titles, start and end times, all-day state, and "
                        + "calendar names. Events stay in memory and are never written to disk, "
                        + "logged, modified, or sent over the network. macOS grants full Calendar "
                        + "access because EventKit has no read-only permission tier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onAppear { store.refreshAuthorization() }
    }

    private var permissionSection: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: permissionSymbol)
                    .font(.system(size: 20))
                    .foregroundStyle(permissionColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(permissionTitle).fontWeight(.medium)
                    Text(permissionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                switch store.authorization {
                case .notDetermined:
                    Button("Request Access", action: store.requestAccess)
                case .denied, .restricted, .writeOnly:
                    Button("Check Again", action: store.refreshAuthorization)
                case .granted:
                    Button(action: { store.refresh() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .padding(.vertical, 6)
        } label: {
            Label("Calendar Access", systemImage: "lock.shield")
                .font(.headline)
        }
    }

    private var calendarsSection: some View {
        GroupBox {
            VStack(spacing: 0) {
                if store.calendars.isEmpty {
                    HStack(spacing: 8) {
                        if store.status == .loading { ProgressView().controlSize(.small) }
                        Text(
                            store.status == .loading
                                ? "Loading calendars…" : "No event calendars are available.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(Array(store.calendars.enumerated()), id: \.element.id) {
                        index, calendar in
                        if index > 0 { Divider() }
                        Toggle(
                            calendar.title,
                            isOn: Binding(
                                get: {
                                    model.isScheduleCalendarEnabled(
                                        calendar.id,
                                        availableIDs: store.calendars.map(\.id))
                                },
                                set: {
                                    model.setScheduleCalendar(
                                        calendar.id, enabled: $0,
                                        availableIDs: store.calendars.map(\.id))
                                }))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .disabled(
                                !model.canDisableScheduleCalendar(
                                    calendar.id,
                                    availableIDs: store.calendars.map(\.id)))
                    }
                }
            }
            .padding(.horizontal, 4)
        } label: {
            Label("Calendars", systemImage: "calendar.badge.clock")
                .font(.headline)
        }
    }

    private var displaySection: some View {
        GroupBox {
            Toggle(
                "Include all-day events",
                isOn: Binding(
                    get: { model.values.schedule.includeAllDay },
                    set: model.setScheduleIncludesAllDay))
                .padding(.vertical, 6)
        } label: {
            Label("Events", systemImage: "list.bullet.rectangle")
                .font(.headline)
        }
    }

    private var refreshSection: some View {
        GroupBox {
            HStack {
                Text("Refresh")
                Spacer()
                Picker(
                    "Schedule refresh interval",
                    selection: Binding(
                        get: { model.values.schedule.refreshInterval },
                        set: model.setScheduleRefreshInterval)
                ) {
                    ForEach(PanelSettings.scheduleRefreshIntervals, id: \.self) {
                        Text(refreshTitle($0)).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }
            .padding(.top, 4)
        } label: {
            Label("Polling", systemImage: "timer")
                .font(.headline)
        }
    }

    private var permissionTitle: String {
        switch store.authorization {
        case .notDetermined: "Calendar access has not been requested"
        case .granted: "Calendar access granted"
        case .writeOnly: "Read access is not granted"
        case .denied: "Calendar access denied"
        case .restricted: "Calendar access restricted"
        }
    }

    private var permissionDetail: String {
        switch store.authorization {
        case .notDetermined:
            "Access is requested only after you press the button."
        case .granted:
            "DockDeck reads upcoming events without changing them."
        case .writeOnly:
            "Allow full access in System Settings → Privacy & Security → Calendars."
        case .denied:
            "Enable DockDeck in System Settings → Privacy & Security → Calendars."
        case .restricted:
            "Calendar access is restricted by this Mac's policy."
        }
    }

    private var permissionSymbol: String {
        store.authorization.canRead ? "checkmark.circle.fill" : "calendar.badge.exclamationmark"
    }

    private var permissionColor: Color {
        store.authorization.canRead ? .green : .orange
    }

    private func refreshTitle(_ interval: TimeInterval) -> String {
        interval < 60 ? "\(Int(interval)) seconds" : "\(Int(interval / 60)) minutes"
    }
}
