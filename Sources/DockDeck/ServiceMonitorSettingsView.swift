import Cocoa
import SwiftUI

struct ServiceMonitorSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 10) {
                        if model.values.serviceMonitor.endpoints.isEmpty {
                            Text("Add up to four HTTPS health or service URLs.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(model.values.serviceMonitor.endpoints) { endpoint in
                                ServiceMonitorEndpointRow(endpoint: endpoint, model: model)
                                if endpoint.id != model.values.serviceMonitor.endpoints.last?.id {
                                    Divider()
                                }
                            }
                        }

                        HStack {
                            Button(action: model.addServiceMonitorEndpoint) {
                                Label("Add Service", systemImage: "plus")
                            }
                            .disabled(
                                model.values.serviceMonitor.endpoints.count
                                    >= ServiceMonitorEndpoint.maximumCount)
                            Spacer()
                            Text(
                                "\(model.values.serviceMonitor.endpoints.count)"
                                    + "/\(ServiceMonitorEndpoint.maximumCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Services", systemImage: "server.rack")
                        .font(.headline)
                }

                GroupBox {
                    SettingsPickerRow(title: "Refresh") {
                        Picker(
                            "Service Monitor refresh interval",
                            selection: Binding(
                                get: { model.values.serviceMonitor.refreshInterval },
                                set: model.setServiceMonitorRefreshInterval)
                        ) {
                            ForEach(PanelSettings.serviceMonitorRefreshIntervals, id: \.self) {
                                Text("\(Int($0)) seconds").tag($0)
                            }
                        }
                        .labelsHidden()
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Polling", systemImage: "timer")
                        .font(.headline)
                }

                Text(
                    "Checks use an ephemeral, cookie-free HEAD request. Public services require "
                        + "HTTPS; HTTP is limited to local addresses. URLs containing credentials "
                        + "or common secret query fields are rejected and never saved. Avoid "
                        + "secret-bearing URL paths. Local addresses may request macOS Local "
                        + "Network permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
private struct ServiceMonitorEndpointRow: View {
    let endpoint: ServiceMonitorEndpoint
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField(
                    "Name",
                    text: Binding(
                        get: { currentEndpoint.name },
                        set: { model.setServiceMonitorEndpointName(endpoint.id, name: $0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                TextField(
                    "https://status.example.com/health",
                    text: Binding(
                        get: { currentEndpoint.urlString },
                        set: { model.setServiceMonitorEndpointURL(endpoint.id, urlString: $0) }))
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.removeServiceMonitorEndpoint(endpoint.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove \(currentEndpoint.displayName)")
                .accessibilityLabel("Remove \(currentEndpoint.displayName)")
            }

            if let message = ServiceMonitorURLValidator.validationMessage(
                currentEndpoint.urlString)
            {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private var currentEndpoint: ServiceMonitorEndpoint {
        model.values.serviceMonitor.endpoints.first { $0.id == endpoint.id } ?? endpoint
    }
}
