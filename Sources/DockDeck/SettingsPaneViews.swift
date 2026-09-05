import Cocoa
import SwiftUI
import UniformTypeIdentifiers

enum DeckModuleDragPayload {
    static let contentType = UTType.utf8PlainText

    private static let prefix = "dockdeck-module:"

    static func itemProvider(for module: PanelModuleID) -> NSItemProvider {
        NSItemProvider(object: "\(prefix)\(module.rawValue)" as NSString)
    }

    static func moduleID(from text: String) -> PanelModuleID? {
        guard text.hasPrefix(prefix) else { return nil }
        let module = PanelModuleID(rawValue: String(text.dropFirst(prefix.count)))
        return PanelModuleRegistry.definition(for: module) == nil ? nil : module
    }
}

struct DecksSettingsView: View {
    @ObservedObject var model: SettingsPanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var moduleRelocation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let app = NSApp.delegate as? AppDelegate {
                    DeckProfileControls(store: app.deckProfiles)
                }
                DeckAutoSlideControls(model: model)

                HStack(alignment: .top, spacing: 14) {
                    DeckPreviewCard(
                        side: .left, model: model, namespace: moduleRelocation)
                    DeckPreviewCard(
                        side: .right, model: model, namespace: moduleRelocation)
                }

                InactiveModulesCard(model: model, namespace: moduleRelocation)

                HStack {
                    Button(action: model.swapDecks) {
                        Label("Swap Left and Right Decks", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text("Drag the ≡ handle to arrange, activate, or hide modules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .animation(relocationAnimation, value: model.values.deckConfiguration)
        }
    }

    private var relocationAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }
}

private struct DeckAutoSlideControls: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Check Auto on at least two enabled cards in the same Deck.")
                Text(
                    "Participating Decks advance together. The wheel still visits every "
                        + "enabled card; a manual-only selection pauses that Deck. Terminal "
                        + "participates only while compact and idle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                HStack(spacing: 8) {
                    Text("Interval")
                    Spacer()
                    Button("5s") { model.setAutoSlideInterval(5) }
                        .buttonStyle(.bordered)
                    Button("10s") { model.setAutoSlideInterval(10) }
                        .buttonStyle(.bordered)
                    HStack(spacing: 4) {
                        TextField("Seconds", value: interval, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 42)
                        Text("sec")
                            .foregroundStyle(.secondary)
                        Stepper("Auto-slide interval", value: interval, in: intervalRange)
                            .labelsHidden()
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Automatic Slide", systemImage: "play.square.stack")
                .font(.headline)
        }
    }

    private var intervalRange: ClosedRange<Int> {
        Int(DeckAutoSlideSettings.minimumInterval)...Int(DeckAutoSlideSettings.maximumInterval)
    }

    private var interval: Binding<Int> {
        Binding(
            get: { Int(model.values.deckAutoSlide.interval) },
            set: { model.setAutoSlideInterval(TimeInterval($0)) })
    }
}

private struct DeckPreviewCard: View {
    let side: PanelSide
    @ObservedObject var model: SettingsPanelModel
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTarget = false

    private var title: String { side == .left ? "Left Deck" : "Right Deck" }
    private var definitions: [PanelModuleDefinition] {
        model.enabledModuleDefinitions(on: side)
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 6) {
                if definitions.isEmpty {
                    EmptyDeckDropZone(
                        isTargeted: isDropTarget,
                        targetAnimation: targetAnimation)
                } else {
                    HStack(spacing: 8) {
                        Text("MODULE")
                        Spacer()
                        Text("AUTO").frame(width: 36)
                        Text("SHOW").frame(width: 36)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)

                    ForEach(definitions) { definition in
                        DeckModuleCard(
                            definition: definition,
                            side: side,
                            model: model,
                            namespace: namespace)
                    }
                }
            }
            .animation(relocationAnimation, value: definitions.map(\.id))
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .top)
        } label: {
            Label(title, systemImage: "rectangle.stack")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(isDropTarget ? 1.008 : 1)
        .animation(targetAnimation, value: isDropTarget)
        .onDrop(
            of: [DeckModuleDragPayload.contentType],
            delegate: DeckModuleDropDelegate(
                side: side,
                target: nil,
                model: model,
                relocationAnimation: relocationAnimation,
                isTargeted: $isDropTarget))
    }

    private var relocationAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private var targetAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }
}

private struct EmptyDeckDropZone: View {
    let isTargeted: Bool
    let targetAnimation: Animation?

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "square.and.arrow.down")
                .font(.title3)
            Text("Drop modules here")
                .font(.callout.weight(.medium))
            Text("This side stays hidden while empty.")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isTargeted
                        ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(0.025)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: [5, 4])))
        .animation(targetAnimation, value: isTargeted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty deck. Drop modules here. This side stays hidden.")
    }
}

private struct InactiveModulesCard: View {
    @ObservedObject var model: SettingsPanelModel
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTarget = false

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Drag into a Deck to activate. Show places a module in the shorter Deck; "
                        + "ties go left.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.inactiveModuleDefinitions.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "checkmark.circle")
                            .font(.title3)
                        Text("All modules are active")
                            .font(.callout.weight(.medium))
                        Text("Drop a Deck card here to hide it.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(model.inactiveModuleDefinitions) { definition in
                            InactiveDeckModuleCard(
                                definition: definition,
                                model: model,
                                namespace: namespace)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .animation(relocationAnimation, value: model.inactiveModuleDefinitions.map(\.id))
        } label: {
            Label("Inactive Modules", systemImage: "archivebox")
                .font(.headline)
        }
        .scaleEffect(isDropTarget ? 1.004 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isDropTarget ? Color.accentColor : .clear,
                    lineWidth: isDropTarget ? 1.5 : 0))
        .animation(targetAnimation, value: isDropTarget)
        .onDrop(
            of: [DeckModuleDragPayload.contentType],
            delegate: InactiveModuleDropDelegate(
                model: model,
                relocationAnimation: relocationAnimation,
                isTargeted: $isDropTarget))
    }

    private var relocationAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    private var targetAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }
}

private struct InactiveDeckModuleCard: View {
    let definition: PanelModuleDefinition
    @ObservedObject var model: SettingsPanelModel
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 28)
                .contentShape(Rectangle())
                .onDrag {
                    DeckModuleDragPayload.itemProvider(for: definition.id)
                } preview: {
                    DeckModuleDragPreview(definition: definition, isEnabled: false)
                }
                .accessibilityLabel("Drag \(definition.title)")
            Image(systemName: definition.symbolName)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(definition.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                Text(definition.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle(
                "Show \(definition.title)",
                isOn: Binding(
                    get: { false },
                    set: { enabled in
                        guard enabled else { return }
                        withAnimation(relocationAnimation) {
                            model.setEnabled(true, for: definition.id)
                        }
                    }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 36)
                .help("Show in the Deck with fewer active modules")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1))
        .opacity(0.72)
        .matchedGeometryEffect(id: definition.id, in: namespace)
        .transition(.scale(scale: 0.97).combined(with: .opacity))
        .contentShape(Rectangle())
        .contextMenu {
            if let pane = definition.settingsPane {
                Button("Configure \(definition.title)…") { model.selectPane(pane) }
                Divider()
            }
            Button("Show in Left Deck") {
                withAnimation(relocationAnimation) {
                    model.activateModule(definition.id, on: .left)
                }
            }
            Button("Show in Right Deck") {
                withAnimation(relocationAnimation) {
                    model.activateModule(definition.id, on: .right)
                }
            }
        }
        .accessibilityAction(named: Text("Show in Left Deck")) {
            withAnimation(relocationAnimation) {
                model.activateModule(definition.id, on: .left)
            }
        }
        .accessibilityAction(named: Text("Show in Right Deck")) {
            withAnimation(relocationAnimation) {
                model.activateModule(definition.id, on: .right)
            }
        }
        .help("Drag the ≡ handle into a Deck, or check Show to activate")
    }

    private var relocationAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }
}

private struct DeckModuleCard: View {
    let definition: PanelModuleDefinition
    let side: PanelSide
    @ObservedObject var model: SettingsPanelModel
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 28)
                .contentShape(Rectangle())
                .onDrag {
                    DeckModuleDragPayload.itemProvider(for: definition.id)
                } preview: {
                    DeckModuleDragPreview(definition: definition, isEnabled: isEnabled)
                }
                .accessibilityLabel("Drag \(definition.title)")
            Image(systemName: definition.symbolName)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(definition.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                Text(definition.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle(
                "Automatically slide \(definition.title)",
                isOn: Binding(
                    get: { model.isAutoSliding(definition.id) },
                    set: { model.setAutoSlideEnabled($0, for: definition.id) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 36)
                .disabled(!isEnabled)
                .help(autoSlideHelp)
            Toggle(
                "Show \(definition.title)",
                isOn: Binding(
                    get: { model.isEnabled(definition.id) },
                    set: { enabled in
                        withAnimation(relocationAnimation) {
                            model.setEnabled(enabled, for: definition.id)
                        }
                    }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 36)
                .disabled(!model.canDisable(definition.id))
                .help(
                    model.canDisable(definition.id)
                        ? "Run and show \(definition.title)"
                        : "DockDeck keeps one module enabled so Settings remains accessible")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isDropTarget
                        ? Color.accentColor.opacity(0.12)
                        : isRecentlyActivated
                            ? Color.accentColor.opacity(0.16)
                            : Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isDropTarget || isRecentlyActivated
                        ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isDropTarget || isRecentlyActivated ? 1.5 : 1))
        .scaleEffect(isDropTarget ? 1.015 : 1)
        .shadow(
            color: isDropTarget || isRecentlyActivated
                ? Color.accentColor.opacity(0.18) : .clear,
            radius: 5,
            y: 2)
        .animation(targetAnimation, value: isDropTarget)
        .animation(highlightAnimation, value: isRecentlyActivated)
        .matchedGeometryEffect(id: definition.id, in: namespace)
        .transition(.scale(scale: 0.97).combined(with: .opacity))
        .contentShape(Rectangle())
        .onDrop(
            of: [DeckModuleDragPayload.contentType],
            delegate: DeckModuleDropDelegate(
                side: side,
                target: definition.id,
                model: model,
                relocationAnimation: relocationAnimation,
                isTargeted: $isDropTarget))
        .contextMenu {
            if let pane = definition.settingsPane {
                Button("Configure \(definition.title)…") { model.selectPane(pane) }
                Divider()
            }
            let destination = side.opposite
            Button("Move to \(destination == .left ? "Left" : "Right") Deck") {
                withAnimation(relocationAnimation) {
                    model.moveModule(definition.id, to: destination)
                }
            }
            Button("Move to Inactive Modules") {
                withAnimation(relocationAnimation) {
                    model.setEnabled(false, for: definition.id)
                }
            }
            .disabled(!model.canDisable(definition.id))
            Divider()
            Button("Move Up") { model.moveModuleUp(definition.id) }
                .disabled(!model.canMoveModuleUp(definition.id))
            Button("Move Down") { model.moveModuleDown(definition.id) }
                .disabled(!model.canMoveModuleDown(definition.id))
        }
        .accessibilityAction(
            named: Text("Move to \(side.opposite == .left ? "Left" : "Right") Deck")
        ) {
            withAnimation(relocationAnimation) {
                model.moveModule(definition.id, to: side.opposite)
            }
        }
        .accessibilityAction(named: Text("Move to Inactive Modules")) {
            guard model.canDisable(definition.id) else { return }
            withAnimation(relocationAnimation) {
                model.setEnabled(false, for: definition.id)
            }
        }
        .help("Drag the ≡ handle to move or reorder \(definition.title)")
    }

    private var isEnabled: Bool { model.isEnabled(definition.id) }
    private var autoSlideHelp: String {
        if definition.id == .terminal {
            return "Include Terminal while compact and idle; focusing it pauses automatic slides"
        }
        return "Include \(definition.title) in automatic slides"
    }
    private var isRecentlyActivated: Bool {
        !reduceMotion && model.recentlyActivatedModule == definition.id
    }

    private var relocationAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private var targetAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    private var highlightAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.12)
    }
}

private struct DeckModuleDragPreview: View {
    let definition: PanelModuleDefinition
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
            Image(systemName: definition.symbolName)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(definition.title)
                    .fontWeight(.semibold)
                Text(definition.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.accentColor.opacity(0.45)))
        .opacity(isEnabled ? 1 : 0.7)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .fixedSize()
    }
}

private struct DeckModuleDropDelegate: DropDelegate {
    let side: PanelSide
    let target: PanelModuleID?
    let model: SettingsPanelModel
    let relocationAnimation: Animation?
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [DeckModuleDragPayload.contentType])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        guard target != nil else { return }
        moveModule(from: info, onlyWhileTargeted: true)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        return moveModule(from: info, onlyWhileTargeted: false)
    }

    @discardableResult
    private func moveModule(from info: DropInfo, onlyWhileTargeted: Bool) -> Bool {
        guard
            let provider = info.itemProviders(
                for: [DeckModuleDragPayload.contentType]
            ).first
        else { return false }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString,
                let module = DeckModuleDragPayload.moduleID(from: text as String)
            else { return }
            DispatchQueue.main.async {
                guard !onlyWhileTargeted
                    || (isTargeted && model.isEnabled(module))
                else { return }
                withAnimation(relocationAnimation) {
                    if model.isEnabled(module) {
                        model.moveModule(module, to: side, before: target)
                    } else {
                        model.activateModule(module, on: side, before: target)
                    }
                }
            }
        }
        return true
    }
}

private struct InactiveModuleDropDelegate: DropDelegate {
    let model: SettingsPanelModel
    let relocationAnimation: Animation?
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [DeckModuleDragPayload.contentType])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard
            let provider = info.itemProviders(
                for: [DeckModuleDragPayload.contentType]
            ).first
        else { return false }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString,
                let module = DeckModuleDragPayload.moduleID(from: text as String)
            else { return }
            DispatchQueue.main.async {
                withAnimation(relocationAnimation) {
                    model.setEnabled(false, for: module)
                }
            }
        }
        return true
    }
}
