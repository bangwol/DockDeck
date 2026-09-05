import AppIntents
import AppKit

// Kept self-contained so SwiftPM packaging can extract App Intents metadata.
enum DockDeckIntentCommand: Equatable {
    case refresh, startFocus, switchProfile(String)

    func validated() throws -> Self {
        guard case .switchProfile(let input) = self else { return self }
        guard input.utf8.count <= 64 * 1_024 else { throw DockDeckIntentError.invalidProfile }
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 48,
            !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw DockDeckIntentError.invalidProfile }
        return .switchProfile(name)
    }
}

enum DockDeckIntentError: LocalizedError {
    case unavailable, focusDisabled, invalidProfile, profileNotFound
    var errorDescription: String? {
        switch self {
        case .unavailable: "Open the installed DockDeck app before running this action."
        case .focusDisabled: "Enable Focus Timer in DockDeck settings before starting focus."
        case .invalidProfile: "Enter a saved profile name of 1–48 characters."
        case .profileNotFound: "No saved deck profile matches that name."
        }
    }
}

@MainActor protocol DockDeckIntentHandling: AnyObject {
    func performDockDeckCommand(_ command: DockDeckIntentCommand) throws
}

struct RefreshDockDeckIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh DockDeck"
    static var description = IntentDescription("Refresh enabled modules and update the Dock layout.")
    static var openAppWhenRun: Bool { true }

    @MainActor func perform() async throws -> some IntentResult {
        guard let handler = NSApp.delegate as? DockDeckIntentHandling else { throw DockDeckIntentError.unavailable }
        try handler.performDockDeckCommand(.refresh)
        return .result()
    }
}

struct StartDockDeckFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start DockDeck Focus"
    static var description = IntentDescription("Start or resume a focus period without pausing one already running.")
    static var openAppWhenRun: Bool { true }

    @MainActor func perform() async throws -> some IntentResult {
        guard let handler = NSApp.delegate as? DockDeckIntentHandling else { throw DockDeckIntentError.unavailable }
        try handler.performDockDeckCommand(.startFocus)
        return .result()
    }
}

struct SwitchDockDeckProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch DockDeck Profile"
    static var description = IntentDescription("Apply a saved deck layout by name. Running Terminal sessions stay alive.")
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Profile name") var profileName: String

    @MainActor func perform() async throws -> some IntentResult {
        guard let handler = NSApp.delegate as? DockDeckIntentHandling else { throw DockDeckIntentError.unavailable }
        try handler.performDockDeckCommand(try DockDeckIntentCommand.switchProfile(profileName).validated())
        return .result()
    }
}
