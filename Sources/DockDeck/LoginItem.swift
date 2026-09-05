import AppKit
import ServiceManagement
import SwiftUI

enum LoginItemStatus: String {
    case enabled, requiresApproval = "requires-approval"
    case notRegistered = "not-registered", notFound = "not-found"
    var isRequested: Bool { self == .enabled || self == .requiresApproval }
    var label: String {
        switch self {
        case .enabled: L10n.text("Enabled")
        case .requiresApproval: L10n.text("Approval required in System Settings")
        case .notRegistered: L10n.text("Disabled")
        case .notFound: L10n.text("Install DockDeck in Applications first")
        }
    }
}

protocol LoginItemControlling {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

struct NativeLoginItem: LoginItemControlling {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notFound
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

final class LoginItemStore: ObservableObject {
    @Published private(set) var status: LoginItemStatus
    @Published private(set) var error: String?
    private let service: any LoginItemControlling

    init(service: any LoginItemControlling = NativeLoginItem()) {
        self.service = service
        status = service.status
    }

    func refresh() { status = service.status }

    @discardableResult func setEnabled(_ enabled: Bool) -> Bool {
        error = nil
        refresh()
        do {
            if enabled, !status.isRequested { try service.register() }
            if !enabled, status.isRequested { try service.unregister() }
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
        return error == nil && (enabled ? status.isRequested : !status.isRequested)
    }
}

struct StartupSettingsView: View {
    @ObservedObject var store: LoginItemStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(L10n.text("Launch at Login"), isOn: Binding(
                get: { store.status.isRequested }, set: { store.setEnabled($0) }))
            Text(store.status.label).foregroundStyle(.secondary)
            Text(L10n.text("Changing this setting affects future logins. DockDeck keeps running now."))
                .font(.callout)
            if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Button(L10n.text("Open Login Items Settings")) { SMAppService.openSystemSettingsLoginItems() }
            Spacer()
        }
        .padding(24)
        .onAppear { store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refresh() }
    }
}

enum DockDeckControl: String {
    case loginStatus = "--login-item-status"
    case enableLogin = "--enable-login-item"
    case disableLogin = "--disable-login-item"
    case stopInstalled = "--stop-installed-app"

    static func parse(_ arguments: [String]) -> Self? {
        arguments.count == 1 ? Self(rawValue: arguments[0]) : nil
    }

    func run() -> Int32 {
        if self == .stopInstalled {
            let installed = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/DockDeck.app").standardizedFileURL
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.dockdeck.app")
                .filter { $0.processIdentifier != getpid() && $0.bundleURL?.standardizedFileURL == installed }
            running.forEach { _ = $0.terminate() }
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while running.contains(where: { !$0.isTerminated }), ProcessInfo.processInfo.systemUptime < deadline {
                // NSRunningApplication updates termination state through the run loop.
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            return running.allSatisfy(\.isTerminated) ? 0 : 1
        }
        let store = LoginItemStore()
        let success = self == .loginStatus || store.setEnabled(self == .enableLogin)
        print(store.status.rawValue)
        if let error = store.error { FileHandle.standardError.write(Data((error + "\n").utf8)) }
        return success ? 0 : 1
    }

    static func activateExistingApp() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier, Bundle.main.bundleURL.pathExtension == "app",
            let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: {
                $0.processIdentifier != getpid() && $0.bundleURL?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
            }) else { return false }
        existing.activate(options: .activateIgnoringOtherApps)
        return true
    }

    static func prepareLog() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let descriptor = open(directory.appendingPathComponent("DockDeck.log").path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { return }
            defer { close(descriptor) }
            _ = dup2(descriptor, STDOUT_FILENO)
            _ = dup2(descriptor, STDERR_FILENO)
        } catch { return }
    }
}
