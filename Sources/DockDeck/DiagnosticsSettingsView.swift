import Cocoa
import SwiftUI

struct DiagnosticsSettingsView: View {
    @ObservedObject var store: DiagnosticsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Current local integration status")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: store.refresh) {
                        if store.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isRefreshing)
                }

                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array(store.items.enumerated()), id: \.element.id) {
                            index, item in
                            DiagnosticSettingsRow(item: item)
                            if index < store.items.count - 1 { Divider() }
                        }
                    }
                } label: {
                    Label("Checks", systemImage: "stethoscope")
                        .font(.headline)
                }

                if !store.moduleRuntime.states.isEmpty {
                    ModuleRuntimeDiagnosticsView(snapshot: store.moduleRuntime)
                }

                Text(
                    "Checks run only when this page opens or Refresh is pressed. "
                        + "Command output and account identifiers are discarded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onAppear(perform: store.refresh)
    }
}
private struct ModuleRuntimeDiagnosticsView: View {
    let snapshot: ModuleRuntimeDiagnostics

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    runtimeBadge(
                        snapshot.systemActive ? "SYSTEM ACTIVE" : "SYSTEM PAUSED",
                        color: snapshot.systemActive ? .green : .blue)
                    if snapshot.constrained {
                        runtimeBadge("REDUCED CADENCE", color: .orange)
                    }
                    Spacer()
                }
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 6
                ) {
                    ForEach(PanelModuleRegistry.all) { definition in
                        if let state = snapshot.states[definition.id] {
                            HStack(spacing: 6) {
                                Image(systemName: definition.symbolName)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 15)
                                Text(definition.title)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(title(state))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(color(state))
                            }
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .frame(height: 26)
                            .background(
                                .secondary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Module Runtime", systemImage: "waveform.path.ecg")
                .font(.headline)
        }
    }

    private func runtimeBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func title(_ state: ModuleRuntimeCoordinator.State) -> String {
        switch state {
        case .stopped: "DISABLED"
        case .suspended: "PAUSED"
        case .background: "BACKGROUND"
        case .visible: "VISIBLE"
        }
    }

    private func color(_ state: ModuleRuntimeCoordinator.State) -> Color {
        switch state {
        case .stopped: .secondary
        case .suspended: .blue
        case .background: .secondary
        case .visible: .green
        }
    }
}

private struct DiagnosticSettingsRow: View {
    let item: DiagnosticCheckItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbolName)
                .foregroundStyle(statusColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .fontWeight(.medium)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(lastSuccessText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch item.state {
        case .checking: "CHECKING"
        case .ready: "READY"
        case .warning: "CHECK"
        case .unavailable: "MISSING"
        }
    }

    private var statusColor: Color {
        switch item.state {
        case .checking: .secondary
        case .ready: .green
        case .warning: .orange
        case .unavailable: .red
        }
    }

    private var lastSuccessText: String {
        guard let date = item.lastSuccessfulAt else { return "No successful check" }
        return "Last OK " + date.formatted(date: .omitted, time: .shortened)
    }
}
