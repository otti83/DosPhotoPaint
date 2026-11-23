import SwiftUI

struct PaintSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsTabForm {
            Section(String(localized: "New Canvas", table: "Settings")) {
                SettingsIntField(title: String(localized: "Width", table: "Settings"),
                                 value: $settings.paintDefaultWidth, range: AppSettings.canvasDimensionRange, unit: "px")
                SettingsIntField(title: String(localized: "Height", table: "Settings"),
                                 value: $settings.paintDefaultHeight, range: AppSettings.canvasDimensionRange, unit: "px")
                Toggle(String(localized: "Transparent background", table: "Settings"),
                       isOn: $settings.paintTransparentBackground)
                ColorPicker(String(localized: "Background color", table: "Settings"),
                            selection: $settings.paintDefaultBackground.swiftUIColor, supportsOpacity: false)
                    .disabled(settings.paintTransparentBackground)
            }
            Section(String(localized: "Tools", table: "Settings")) {
                SettingsEnumPicker(String(localized: "Tool palette position", table: "Settings"),
                                   selection: $settings.paintToolPalettePosition) { $0.settingsLabel }
                Picker(String(localized: "Initial tool", table: "Settings"), selection: $settings.paintInitialTool) {
                    ForEach(ToolKind.allCases) { Text($0.localizedName).tag($0.rawValue) }
                }
                SettingsIntField(title: String(localized: "Initial line width", table: "Settings"),
                                 value: $settings.paintInitialLineWidth, range: AppSettings.lineWidthRange, unit: "px")
                ColorPicker(String(localized: "Initial color", table: "Settings"),
                            selection: $settings.paintInitialColor.swiftUIColor, supportsOpacity: true)
                Toggle(String(localized: "Anti-aliasing", table: "Settings"), isOn: $settings.paintAntialiasing)
                Toggle(String(localized: "Remember tool settings", table: "Settings"),
                       isOn: $settings.paintRememberToolSettings)
            }
            Section(String(localized: "Canvas", table: "Settings")) {
                Toggle(String(localized: "Show grid", table: "Settings"), isOn: $settings.paintShowGrid)
                SettingsIntField(title: String(localized: "Grid spacing", table: "Settings"),
                                 value: $settings.paintGridSpacing, range: AppSettings.gridSpacingRange, unit: "px")
                    .disabled(!settings.paintShowGrid)
                SettingsEnumPicker(String(localized: "Pixel grid", table: "Settings"),
                                   selection: $settings.paintPixelGrid) { $0.settingsLabel }
                Toggle(String(localized: "Show selection outline", table: "Settings"),
                       isOn: $settings.paintShowSelectionOutline)
            }
            Section {
                SettingsIntField(title: String(localized: "Undo levels", table: "Settings"),
                                 value: $settings.paintUndoLevels, range: AppSettings.undoLevelsRange)
            } header: {
                Text("History", tableName: "Settings")
            } footer: {
                Text("More undo levels use more memory. Applies to open documents immediately.", tableName: "Settings")
            }
        }
    }
}
