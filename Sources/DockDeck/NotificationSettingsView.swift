import Cocoa
import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Allow local notifications")
                            Text("macOS asks for permission only when you turn this on.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(
                            "Allow local notifications",
                            isOn: Binding(
                                get: { model.values.notifications.enabled },
                                set: model.setNotificationsEnabled))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Notifications", systemImage: "bell.badge")
                        .font(.headline)
                }

                GroupBox {
                    VStack(spacing: 12) {
                        SettingsSwitchRow(
                            title: "Usage limits",
                            subtitle: "Alert when a live quota window reaches the threshold.",
                            isOn: Binding(
                                get: { model.values.notifications.usageAlerts },
                                set: model.setUsageAlertsEnabled))
                        Divider()
                        SettingsPickerRow(title: "Remaining") {
                            Picker(
                                "Usage remaining threshold",
                                selection: Binding(
                                    get: {
                                        model.values.notifications.usageRemainingThreshold
                                    },
                                    set: model.setUsageAlertThreshold)
                            ) {
                                ForEach(DockNotificationSettings.usageThresholds, id: \.self) {
                                    Text("\($0)%").tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Usage", systemImage: "chart.bar")
                        .font(.headline)
                }
                .disabled(!model.values.notifications.enabled)

                GroupBox {
                    VStack(spacing: 12) {
                        SettingsSwitchRow(
                            title: "Service failures",
                            subtitle: "Alert once when a configured endpoint goes down.",
                            isOn: Binding(
                                get: {
                                    model.values.notifications.serviceFailureAlerts
                                },
                                set: model.setServiceFailureAlertsEnabled))
                        Divider()
                        SettingsSwitchRow(
                            title: "Service recoveries",
                            subtitle: "Alert when a failed endpoint responds again.",
                            isOn: Binding(
                                get: {
                                    model.values.notifications.serviceRecoveryAlerts
                                },
                                set: model.setServiceRecoveryAlertsEnabled))
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Service Monitor", systemImage: "server.rack")
                        .font(.headline)
                }
                .disabled(!model.values.notifications.enabled)

                GroupBox {
                    VStack(spacing: 12) {
                        SettingsSwitchRow(
                            title: "Low battery",
                            subtitle: "Alert on battery power when charge reaches the threshold.",
                            isOn: Binding(
                                get: { model.values.notifications.batteryAlerts },
                                set: model.setBatteryAlertsEnabled))
                        Divider()
                        SettingsPickerRow(title: "Remaining") {
                            Picker(
                                "Battery remaining threshold",
                                selection: Binding(
                                    get: {
                                        model.values.notifications.batteryRemainingThreshold
                                    },
                                    set: model.setBatteryAlertThreshold)
                            ) {
                                ForEach(DockNotificationSettings.batteryThresholds, id: \.self) {
                                    Text("\($0)%").tag($0)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Battery", systemImage: "battery.25percent")
                        .font(.headline)
                }
                .disabled(!model.values.notifications.enabled)

                GroupBox {
                    SettingsSwitchRow(
                        title: "Thermal pressure",
                        subtitle: "Alert when macOS reports serious or critical thermal pressure.",
                        isOn: Binding(
                            get: { model.values.notifications.systemThermalAlerts },
                            set: model.setSystemThermalAlertsEnabled))
                        .padding(.top, 4)
                } label: {
                    Label("System Stats", systemImage: "thermometer.medium")
                        .font(.headline)
                }
                .disabled(!model.values.notifications.enabled)

                GroupBox {
                    SettingsSwitchRow(
                        title: "Timer completion",
                        subtitle: "Alert when a focus or break countdown finishes.",
                        isOn: Binding(
                            get: { model.values.notifications.focusTimerAlerts },
                            set: model.setFocusTimerAlertsEnabled))
                        .padding(.top, 4)
                } label: {
                    Label("Focus Timer", systemImage: "timer")
                        .font(.headline)
                }
                .disabled(!model.values.notifications.enabled)

                Text(
                    "Alerts are generated locally from DockDeck's existing module data and only "
                        + "when a condition changes. If macOS access is blocked, allow DockDeck in "
                        + "System Settings → Notifications. Notification previews can include a "
                        + "provider or service name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
