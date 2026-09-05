import Cocoa
import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsPanelModel
    @AppStorage(CompactReadability.preferenceKey) private var largerText = false
    @State private var isConfirmingReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Readable Panels") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Larger text and fewer details", isOn: $largerText)
                        Text("Keeps compact labels at least 10 pt and moves auxiliary details to the detail window. Increase Contrast also enables this layout. Reduce Transparency uses an opaque panel surface.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
                GroupBox {
                    VStack(spacing: 14) {
                        SettingsSliderRow(
                            title: "Corner Radius",
                            valueText: String(
                                format: "%.0f pt", model.values.appearance.cornerRadius),
                            value: Binding(
                                get: { Double(model.values.appearance.cornerRadius) },
                                set: { model.setCornerRadius(CGFloat($0)) }),
                            range: 0...24,
                            step: 1)
                        SettingsSliderRow(
                            title: "Theme Tint",
                            valueText: String(
                                format: "%.0f%%", model.values.appearance.tintOpacity * 100),
                            value: Binding(
                                get: { Double(model.values.appearance.tintOpacity) },
                                set: { model.setTintOpacity(CGFloat($0)) }),
                            range: 0.2...1,
                            step: 0.01)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Panel Surface", systemImage: "circle.lefthalf.filled")
                        .font(.headline)
                }

                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reset Settings")
                            Text("Restore all module and appearance defaults.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset to Defaults") { isConfirmingReset = true }
                            .confirmationDialog(
                                "Reset all DockDeck settings?",
                                isPresented: $isConfirmingReset,
                                titleVisibility: .visible
                            ) {
                                Button("Reset to Defaults", role: .destructive) {
                                    model.onReset?()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(
                                    "Deck layout, Service Monitor URLs, the Weather city, and "
                                        + "appearance return to their defaults. Themes are kept.")
                            }
                    }
                    .padding(.vertical, 6)
                } label: {
                    Label("Defaults", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                }
            }
            .padding(24)
        }
    }
}
