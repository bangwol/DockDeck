import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DeckProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var configuration: PanelDeckConfiguration
    var autoSlideModules: [PanelModuleID]
    var autoSlideInterval: TimeInterval

    var autoSlide: DeckAutoSlideSettings {
        DeckAutoSlideSettings(modules: autoSlideModules, interval: autoSlideInterval)
    }
}

struct DeckProfileArchive: Codable, Equatable {
    static let maximumBytes = 64 * 1_024
    var schemaVersion = 1
    var profiles: [DeckProfile] = []

    func validated() throws -> Self {
        guard schemaVersion == 1 else { throw ProfileError.version }
        guard profiles.count <= 8, Set(profiles.map(\.id)).count == profiles.count else { throw ProfileError.profiles }
        let known = Set(PanelModuleID.builtIns + [.network])
        for (index, profile) in profiles.enumerated() {
            guard !profiles.prefix(index).contains(where: {
                $0.name.caseInsensitiveCompare(profile.name) == .orderedSame
            }) else { throw ProfileError.names }
            guard !profile.name.isEmpty, profile.name.count <= 48,
                profile.name == profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
                profile.name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw ProfileError.names }
            let layout = profile.configuration.left + profile.configuration.right
            let enabled = profile.configuration.enabled
            guard Set(layout).count == layout.count, Set(layout).isSubset(of: known),
                !enabled.isEmpty, Set(enabled).count == enabled.count,
                Set(enabled).isSubset(of: Set(layout)) else { throw ProfileError.modules }
            guard Set(profile.autoSlideModules).count == profile.autoSlideModules.count,
                Set(profile.autoSlideModules).isSubset(of: Set(enabled)),
                profile.autoSlideInterval.isFinite,
                (DeckAutoSlideSettings.minimumInterval...DeckAutoSlideSettings.maximumInterval).contains(profile.autoSlideInterval)
            else { throw ProfileError.autoSlide }
        }
        return self
    }

    static func read(from url: URL) throws -> Self {
        guard url.isFileURL, try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw ProfileError.unreadable }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw ProfileError.size }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated())
        guard data.count <= Self.maximumBytes else { throw ProfileError.size }
        return data
    }
}

enum ProfileError: LocalizedError {
    case version, profiles, names, modules, autoSlide, size, unreadable
    var errorDescription: String? {
        switch self {
        case .version: "This profile archive uses an unsupported version."
        case .profiles: "Save up to eight profiles with unique IDs."
        case .names: "Use unique profile names of 1–48 characters without surrounding spaces or control characters."
        case .modules: "Profiles need known, unique module IDs and at least one enabled module assigned to a side."
        case .autoSlide: "Auto-slide must use enabled modules and an interval from 5 to 300 seconds."
        case .size: "The profile archive exceeds 64 KiB."
        case .unreadable: "The existing profile library could not be read. Import a valid backup to replace it."
        }
    }
}

final class DeckProfileStore: ObservableObject {
    @Published private(set) var archive = DeckProfileArchive()
    @Published private(set) var loadError: String?
    let url: URL

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DockDeck/deck-profiles.json")) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { archive = try DeckProfileArchive.read(from: url) }
        catch { loadError = error.localizedDescription }
    }

    func save(name: String, configuration: PanelDeckConfiguration, autoSlide: DeckAutoSlideSettings) throws {
        guard loadError == nil else { throw ProfileError.unreadable }
        var updated = archive
        updated.profiles.append(DeckProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            configuration: configuration,
            autoSlideModules: autoSlide.modules.filter(configuration.enabled.contains), autoSlideInterval: autoSlide.interval))
        try replace(updated)
    }

    func remove(_ id: UUID) throws {
        guard loadError == nil else { throw ProfileError.unreadable }
        var updated = archive
        updated.profiles.removeAll { $0.id == id }
        try replace(updated)
    }

    func replace(_ archive: DeckProfileArchive) throws {
        let data = try archive.data()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        self.archive = archive
        loadError = nil
    }
}

enum DeckProfileTerminalPolicy {
    static func retain(isRunning: Bool, retained: Bool, nextEnabled: Bool) -> Bool {
        !nextEnabled && (isRunning || retained)
    }
}

struct DeckProfileControls: View {
    @ObservedObject var store: DeckProfileStore
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        GroupBox(L10n.text("Saved Deck Profiles")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField(L10n.text("Profile name"), text: $name)
                    Button(L10n.text("Save Current")) {
                        perform {
                            try store.save(name: name, configuration: PanelSettings.deckConfiguration,
                                autoSlide: PanelSettings.deckAutoSlideSettings)
                            name = ""
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.archive.profiles.count >= 8)
                }
                ForEach(store.archive.profiles) { profile in
                    HStack {
                        Button(profile.name) { (NSApp.delegate as? AppDelegate)?.applyDeckProfile(profile) }
                        Text("\(profile.configuration.enabled.count) modules").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.text("Remove")) { perform { try store.remove(profile.id) } }
                    }
                }
                HStack {
                    Button(L10n.text("Export…"), action: exportProfiles).disabled(store.loadError != nil)
                    Button(L10n.text("Import…"), action: importProfiles)
                }
                Text("Profiles save layout and auto-slide only. A running Terminal session stays alive when a profile hides it, until Terminal is enabled again or the app quits. Other hidden modules stop normally.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = error ?? store.loadError { Text(message).font(.caption).foregroundStyle(.red) }
            }.padding(.top, 4)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func exportProfiles() {
        let picker = NSSavePanel()
        picker.allowedContentTypes = [.json]
        picker.nameFieldStringValue = "DockDeck-profiles.json"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        perform { try store.archive.data().write(to: url, options: .atomic) }
    }

    private func importProfiles() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.json]
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        perform {
            let archive = try DeckProfileArchive.read(from: url)
            let alert = NSAlert()
            alert.messageText = L10n.text("Replace saved deck profiles?")
            alert.informativeText = "This imports \(archive.profiles.count) profiles and replaces the saved library. Your current deck stays unchanged.\n\n"
                + archive.profiles.map { "\($0.name) · \($0.configuration.enabled.count) modules" }.joined(separator: "\n")
            alert.addButton(withTitle: L10n.text("Replace Profiles"))
            alert.addButton(withTitle: L10n.text("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try store.replace(archive)
        }
    }
}
