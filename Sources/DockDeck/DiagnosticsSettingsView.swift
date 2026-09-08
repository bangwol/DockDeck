import Cocoa
import SwiftUI

struct DiagnosticsSettingsView: View {
    @ObservedObject var store: DiagnosticsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L10n.text("Current local integration status"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: store.copyReport) {
                        Label(L10n.text("Copy Report"), systemImage: "doc.on.doc")
                    }
                    .help("Copy a redacted diagnostics report")
                    Button(action: store.refresh) {
                        if store.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(L10n.text("Refresh"), systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isRefreshing)
                    .accessibilityLabel(L10n.text("Refresh"))
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
                    Label(L10n.text("Checks"), systemImage: "stethoscope")
                        .font(.headline)
                }

                Text(L10n.text("CLI updates are advisory and separate from sign-in status. Copy a command and run it yourself; DockDeck does not install updates."))
                    .font(.caption).foregroundStyle(.secondary)

                if !store.processes.isEmpty {
                    GroupBox("Command performance (this session)") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(store.processes, id: \.source) { metric in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(metric.source.rawValue).fontWeight(.medium)
                                    Text("Last duration: \(metric.lastDuration, specifier: "%.3f")s · Timeouts: \(metric.timeouts) · Cancellations: \(metric.cancellations)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let success = metric.lastSuccessfulAt {
                                        Text("Last OK \(success.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }.accessibilityElement(children: .combine)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }
                }

                if !store.moduleRuntime.states.isEmpty {
                    ModuleRuntimeDiagnosticsView(snapshot: store.moduleRuntime)
                }

                Text(
                    "Checks run only when this page opens or Refresh is pressed. "
                        + "Copied reports omit details, paths, URLs, command output, and account identifiers.")
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
                                Text(definition.displayTitle)
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
                            .help(stateHelp(definition.id, state: state))
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label(L10n.text("Module Runtime"), systemImage: "waveform.path.ecg")
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

    private func stateHelp(
        _ module: PanelModuleID, state: ModuleRuntimeCoordinator.State
    ) -> String {
        guard let date = snapshot.stateChangedAt[module] else { return title(state) }
        return "\(title(state)) since \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct DiagnosticSettingsRow: View {
    let item: DiagnosticCheckItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: item.symbolName)
                    .foregroundStyle(statusColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).fontWeight(.medium)
                    Text(L10n.text(item.detail))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(statusTitle)
                        .font(.caption.weight(.semibold)).foregroundStyle(statusColor)
                    Text(lastSuccessText)
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            if let info = item.cliUpdate {
                CLIUpdateSettingsRow(info: info, id: item.id)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 9)
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

private struct CLIUpdateSettingsRow: View {
    let info: CLIUpdateInfo
    let id: DiagnosticCheckID
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(format: L10n.text("Installed: %@ · %@"), info.installedVersion?.text ?? "—", info.installation.title))
                .foregroundStyle(.secondary)
                .help(info.executablePath)
            Text(info.status)
                .foregroundStyle(info.updateAvailable ? .orange : .secondary)
                .help(info.checkedAt.map {
                    String(format: L10n.text("Release metadata checked: %@"), $0.formatted(date: .abbreviated, time: .shortened))
                } ?? info.status)
            HStack(spacing: 10) {
                if let command = info.command {
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        copied = pasteboard.setString(command, forType: .string)
                    } label: {
                        Label(L10n.text(copied ? "Copied" : "Copy Update Command"), systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .help(command)
                    .accessibilityLabel(String(format: L10n.text("Copy update command for %@"), id.title))
                    .onChange(of: command) { _ in copied = false }
                }
                if let guideURL {
                    Link(L10n.text("Installation Guide"), destination: guideURL)
                }
            }
        }
        .font(.caption)
    }

    private var guideURL: URL? {
        switch id {
        case .codex: URL(string: "https://github.com/openai/codex#installing-and-running-codex-cli")
        case .claude: URL(string: "https://code.claude.com/docs/en/installation#update-claude-code")
        case .github: URL(string: "https://github.com/cli/cli#installation")
        default: nil
        }
    }
}
