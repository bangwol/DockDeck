import AppKit
import SwiftUI

enum ModuleSearch {
    static func matches(_ query: String, text: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy {
            text.localizedCaseInsensitiveContains(String($0))
        }
    }
}

final class ModulePickerModel: ObservableObject {
    @Published var query = "" { didSet { selection = modules.first?.id } }
    @Published var selection: PanelModuleID?
    let configuration: PanelDeckConfiguration
    let active: Set<PanelModuleID>

    init(configuration: PanelDeckConfiguration, active: Set<PanelModuleID>) {
        self.configuration = configuration
        self.active = active
        selection = modules.first?.id
    }

    var modules: [PanelModuleDefinition] {
        (configuration.left + configuration.right).compactMap { id in
            guard configuration.contains(id), let module = PanelModuleRegistry.definition(for: id),
                ModuleSearch.matches(query, text: "\(module.title) \(module.displayTitle) \(module.subtitle) \(module.settingsPane?.subtitle ?? "") \(id.rawValue)") else { return nil }
            return module
        }
    }

    func move(_ delta: Int) {
        let modules = modules
        guard !modules.isEmpty else { selection = nil; return }
        let current = modules.firstIndex(where: { $0.id == selection }) ?? 0
        selection = modules[min(max(current + min(max(delta, -1), 1), 0), modules.count - 1)].id
    }
}

final class ModulePickerController: NSObject, NSWindowDelegate {
    let window: NSPanel
    private let model: ModulePickerModel
    private var keyMonitor: Any?
    private let onSelect: (PanelModuleID, Bool) -> Void
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void = {}, onSelect: @escaping (PanelModuleID, Bool) -> Void) {
        model = ModulePickerModel(configuration: PanelSettings.deckConfiguration,
            active: Set(PanelSide.allCases.compactMap { PanelSettings.activeModule(on: $0) }))
        window = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 510, height: 390),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.onSelect = onSelect
        self.onClose = onClose
        super.init()
        window.title = L10n.text("Find Module")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ModulePickerView(model: model) { [weak self] detail in
            self?.submit(detail: detail)
        })
        window.center()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, self.window.isKeyWindow,
                event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                (self.window.firstResponder as? NSTextInputClient)?.hasMarkedText() != true else { return event }
            switch event.keyCode {
            case 125: self.model.move(1)
            case 126: self.model.move(-1)
            case 36, 76: self.submit(detail: false)
            case 53: self.window.close()
            default: return event
            }
            return nil
        }
    }

    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        DispatchQueue.main.async(execute: onClose)
    }

    private func submit(detail: Bool) {
        guard let module = model.selection, model.modules.contains(where: { $0.id == module }) else { return }
        window.close()
        onSelect(module, detail)
    }
}

private struct ModulePickerView: View {
    @ObservedObject var model: ModulePickerModel
    let onSelect: (Bool) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            TextField(L10n.text("Search enabled modules"), text: $model.query)
                .textFieldStyle(.roundedBorder).focused($searchFocused)
            ScrollViewReader { proxy in
                List(selection: $model.selection) {
                    ForEach(model.modules) { module in
                        HStack {
                            Label(module.displayTitle, systemImage: module.symbolName)
                            Spacer()
                            Text(model.configuration.side(containing: module.id) == .left ? L10n.text("Left") : L10n.text("Right"))
                                .foregroundStyle(.secondary)
                            if model.active.contains(module.id) {
                                Image(systemName: "checkmark.circle.fill").accessibilityLabel(L10n.text("Currently displayed"))
                            }
                        }
                        .tag(module.id)
                        .onTapGesture(count: 2) { model.selection = module.id; onSelect(false) }
                    }
                }
                .overlay {
                    if model.modules.isEmpty { Text(L10n.text("No matching modules")).foregroundStyle(.secondary) }
                }
                .onChange(of: model.selection) { id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            HStack {
                Text(L10n.text("↑ ↓ Select · Return Open · Esc Close")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Open Detail")) { onSelect(true) }
                    .disabled(model.selection == nil || model.selection == .terminal)
                Button(L10n.text("Show Module")) { onSelect(false) }.disabled(model.selection == nil)
            }
        }
        .padding(16)
        .onAppear { searchFocused = true }
    }
}
