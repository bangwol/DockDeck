import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuickAction: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case app, folder, webpage, shortcut
        var id: Self { self }
        var title: String { switch self { case .app: L10n.text("App"); case .folder: L10n.text("Folder"); case .webpage: L10n.text("Web Page"); case .shortcut: L10n.text("Shortcut") } }
        var symbol: String { switch self { case .app: "app"; case .folder: "folder"; case .webpage: "globe"; case .shortcut: "command" } }
    }
    var id = UUID()
    var name: String
    var kind: Kind
    var target: String

    func validated() throws -> Self {
        guard !name.isEmpty, name.count <= 48, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            !target.isEmpty, target.utf8.count <= 4_096,
            !target.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw QuickActionError.invalid }
        switch kind {
        case .app, .folder:
            guard target.hasPrefix("/"), target.utf8.count < Int(PATH_MAX) else { throw QuickActionError.invalid }
            if kind == .app, URL(fileURLWithPath: target).pathExtension.lowercased() != "app" { throw QuickActionError.invalid }
        case .webpage:
            guard let components = URLComponents(string: target), let scheme = components.scheme?.lowercased(),
                ["http", "https"].contains(scheme), let host = components.host, !host.isEmpty,
                components.user == nil, components.password == nil, components.url != nil else { throw QuickActionError.invalid }
            if let port = components.port, !(1...65_535).contains(port) { throw QuickActionError.invalid }
        case .shortcut:
            guard target.count <= 255, !target.hasPrefix("-"), target == target.trimmingCharacters(in: .whitespacesAndNewlines) else { throw QuickActionError.invalid }
        }
        return self
    }

    static func validated(_ actions: [Self]) throws -> [Self] {
        guard actions.count <= 4, Set(actions.map(\.id)).count == actions.count else { throw QuickActionError.limit }
        return try actions.map { try $0.validated() }
    }
}

enum QuickActionError: LocalizedError {
    case invalid, limit, unreadable, unavailable, failed
    var errorDescription: String? {
        switch self {
        case .invalid: "Use a short name and a valid app/folder path, HTTP(S) URL without credentials, or Shortcut name."
        case .limit: "Save up to four quick actions with unique IDs."
        case .unreadable: "Saved quick actions could not be read. Clear them in settings before saving a new list."
        case .unavailable: "The selected app or folder is unavailable."
        case .failed: "The action could not be opened."
        }
    }
}

enum QuickActionLaunchPolicy {
    static func allows(now: TimeInterval, last: TimeInterval?, running: Bool) -> Bool {
        guard now.isFinite, now >= 0, !running else { return false }
        return last.map { $0.isFinite && now - $0 >= 0.8 } ?? true
    }
}

final class QuickActionStore: ObservableObject {
    static let preferenceKey = "dockdeck.quickActions.v1"
    @Published private(set) var actions: [QuickAction] = []
    @Published private(set) var running: Set<UUID> = []
    @Published private(set) var error: String?
    private var unreadable = false
    private var lastLaunch: [UUID: TimeInterval] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let saved = defaults.object(forKey: Self.preferenceKey) else { return }
        do {
            guard let data = saved as? Data, data.count <= 32 * 1_024 else { throw QuickActionError.unreadable }
            actions = try QuickAction.validated(JSONDecoder().decode([QuickAction].self, from: data))
        } catch { unreadable = true; self.error = QuickActionError.unreadable.localizedDescription }
    }

    func save(_ actions: [QuickAction]) throws {
        guard !unreadable else { throw QuickActionError.unreadable }
        let actions = try QuickAction.validated(actions)
        let data = try JSONEncoder().encode(actions)
        guard data.count <= 32 * 1_024 else { throw QuickActionError.invalid }
        defaults.set(data, forKey: Self.preferenceKey)
        self.actions = actions
        lastLaunch = lastLaunch.filter { id, _ in actions.contains { $0.id == id } }
        error = nil
    }

    func clear() {
        defaults.removeObject(forKey: Self.preferenceKey)
        actions = []
        lastLaunch = [:]
        unreadable = false
        error = nil
    }

    func run(_ id: UUID, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let action = actions.first(where: { $0.id == id }),
            QuickActionLaunchPolicy.allows(now: now, last: lastLaunch[id], running: running.contains(id)) else { return }
        do {
            _ = try action.validated()
            lastLaunch[id] = now
            error = nil
            switch action.kind {
            case .app, .folder:
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: action.target, isDirectory: &directory), directory.boolValue else { throw QuickActionError.unavailable }
                running.insert(id)
                let completion: (NSRunningApplication?, Error?) -> Void = { [weak self] _, error in
                    DispatchQueue.main.async {
                        self?.running.remove(id)
                        if error != nil { self?.error = QuickActionError.failed.localizedDescription }
                    }
                }
                let url = URL(fileURLWithPath: action.target)
                if action.kind == .app {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: completion)
                } else {
                    NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                        configuration: .init(), completionHandler: completion)
                }
            case .webpage:
                guard let url = URL(string: action.target), NSWorkspace.shared.open(url) else { throw QuickActionError.failed }
            case .shortcut:
                running.insert(id)
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let result = Result {
                        _ = try BoundedProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
                            arguments: ["run", action.target], timeout: 30, maximumOutputBytes: 32 * 1_024, diagnosticSource: .quickAction)
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.running.remove(id)
                        if case .failure(let failure) = result {
                            self.error = failure as? BoundedProcessError == .timedOut
                                ? "Shortcut exceeded the 30-second execution limit."
                                : "Shortcut failed or exceeded the 32 KiB output limit."
                        }
                    }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct QuickActionsSettingsView: View {
    @ObservedObject var store: QuickActionStore
    @State private var kind = QuickAction.Kind.app
    @State private var name = ""
    @State private var target = ""
    @State private var error: String?
    @State private var confirmsClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(store.actions) { action in
                    HStack {
                        Label(action.name, systemImage: action.kind.symbol).lineLimit(1)
                        Spacer()
                        Button(store.running.contains(action.id) ? "Running…" : "Run") { store.run(action.id) }
                            .disabled(store.running.contains(action.id))
                        Button(L10n.text("Remove")) { perform { try store.save(store.actions.filter { $0.id != action.id }) } }
                    }
                }
                Divider()
                Picker(L10n.text("Type"), selection: $kind) {
                    ForEach(QuickAction.Kind.allCases) { Text($0.title).tag($0) }
                }.onChange(of: kind) { _ in target = "" }
                TextField(L10n.text("Name"), text: $name)
                HStack {
                    TextField(kind == .shortcut ? "Shortcut name" : kind == .webpage ? "https://example.com" : "Path", text: $target)
                    if kind == .app || kind == .folder { Button(L10n.text("Choose…"), action: chooseTarget) }
                }
                Button(L10n.text("Add Action")) {
                    perform {
                        try store.save(store.actions + [QuickAction(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, target: target)])
                        name = ""; target = ""
                    }
                }.disabled(store.actions.count >= 4)
                Text("Actions run only when selected here or in the Quick Actions app menu. Shortcuts have a 30-second and 32 KiB output limit. Saving or editing never launches an action. Only use Shortcuts you trust.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = error ?? store.error { Text(message).font(.caption).foregroundStyle(.red) }
                Button(L10n.text("Clear Saved Actions")) { confirmsClear = true }
                    .confirmationDialog(L10n.text("Clear all saved quick actions?"), isPresented: $confirmsClear) {
                        Button(L10n.text("Clear"), role: .destructive) { store.clear() }
                    }
            }.padding(24)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func chooseTarget() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = kind == .app
        picker.canChooseDirectories = kind == .folder
        picker.allowsMultipleSelection = false
        if kind == .app { picker.allowedContentTypes = [.applicationBundle] }
        guard picker.runModal() == .OK, let url = picker.url else { return }
        target = url.path
        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
    }
}
