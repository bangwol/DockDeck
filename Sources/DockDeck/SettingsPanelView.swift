import Cocoa
import SwiftUI

final class SettingsPanelView: NSView {
    static let preferredSize = NSSize(width: 700, height: 520)

    private let model: SettingsPanelModel
    private let hostingView: NSHostingView<SettingsRootView>

    var onPaneChange: ((SettingsPaneID) -> Void)? {
        get { model.onPaneChange }
        set { model.onPaneChange = newValue }
    }
    var onChange: ((SettingsPanelChange) -> Void)? {
        get { model.onChange }
        set { model.onChange = newValue }
    }
    var onReset: (() -> Void)? {
        get { model.onReset }
        set { model.onReset = newValue }
    }
    var onCancel: (() -> Void)? {
        get { model.onCancel }
        set { model.onCancel = newValue }
    }

    init(
        selectedPane: SettingsPaneID,
        values: SettingsPanelValues,
        fontNames: [String]
    ) {
        let model = SettingsPanelModel(
            selectedPane: selectedPane, values: values, fontNames: fontNames)
        self.model = model
        hostingView = NSHostingView(rootView: SettingsRootView(model: model))

        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        setAccessibilityLabel("DockDeck Settings")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func selectPane(_ pane: SettingsPaneID) {
        model.selectPane(pane)
    }

    func setValues(_ values: SettingsPanelValues) {
        model.setValues(values)
    }

    @objc override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private struct SettingsRootView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "dock.rectangle")
                        .foregroundStyle(.secondary)
                    Text("DockDeck")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 54)

                List(model.availablePanes, selection: $model.selectedPane) { pane in
                    Label(pane.title, systemImage: pane.symbolName)
                        .tag(pane)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 184)
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            VStack(spacing: 0) {
                SettingsHeader(pane: model.selectedPane)
                Divider()
                selectedPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            minWidth: SettingsPanelView.preferredSize.width,
            minHeight: SettingsPanelView.preferredSize.height)
    }

    @ViewBuilder private var selectedPane: some View {
        switch model.selectedPane {
        case .decks:
            DecksSettingsView(model: model)
        case .terminal:
            TerminalSettingsView(model: model)
        case .usage:
            UsageSettingsView(model: model)
        case .appearance:
            AppearanceSettingsView(model: model)
        }
    }
}

private struct SettingsHeader: View {
    let pane: SettingsPaneID

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pane.symbolName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.title2.weight(.semibold))
                Text(pane.subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
    }
}
