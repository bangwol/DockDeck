import Cocoa
import SwiftUI

struct TerminalSettingsView: View {
    @ObservedObject var model: SettingsPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(spacing: 14) {
                        SettingsSliderRow(
                            title: "Width",
                            valueText: String(
                                format: "%.2f×", model.values.terminal.focusWidthMultiplier),
                            value: Binding(
                                get: {
                                    Double(model.values.terminal.focusWidthMultiplier)
                                },
                                set: { model.setFocusWidthMultiplier(CGFloat($0)) }),
                            range: Double(DockPanelLayout.minimumFocusedWidthMultiplier)
                                ... Double(DockPanelLayout.maximumFocusedWidthMultiplier),
                            step: 0.25)
                        SettingsSliderRow(
                            title: "Height",
                            valueText: String(
                                format: "%.2f×", model.values.terminal.focusHeightMultiplier),
                            value: Binding(
                                get: {
                                    Double(model.values.terminal.focusHeightMultiplier)
                                },
                                set: { model.setFocusHeightMultiplier(CGFloat($0)) }),
                            range: Double(DockPanelLayout.minimumFocusedHeightMultiplier)
                                ... Double(DockPanelLayout.maximumFocusedHeightMultiplier),
                            step: 0.25)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Focused Size", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                }

                GroupBox {
                    SettingsPickerRow(title: "Font") {
                        Picker(
                            "Terminal font",
                            selection: Binding(
                                get: { model.values.terminal.fontName },
                                set: model.setTerminalFontName)
                        ) {
                            ForEach(model.fontNames, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Text", systemImage: "textformat")
                        .font(.headline)
                }
            }
            .padding(24)
        }
    }
}
