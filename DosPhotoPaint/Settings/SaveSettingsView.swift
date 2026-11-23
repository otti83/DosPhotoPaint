import SwiftUI

struct SaveSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsTabForm {
            Section(String(localized: "Format", table: "Settings")) {
                SettingsEnumPicker(String(localized: "Default format", table: "Settings"),
                                   selection: $settings.saveDefaultFormat) { $0.settingsLabel }
                LabeledContent(String(localized: "JPEG quality", table: "Settings")) {
                    HStack {
                        Slider(value: $settings.saveJPEGQuality, in: AppSettings.jpegQualityRange)
                            .frame(width: 180)
                        Text(settings.saveJPEGQuality, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                ColorPicker(String(localized: "Background for transparent areas in JPEG", table: "Settings"),
                            selection: $settings.saveJPEGBackground.swiftUIColor, supportsOpacity: false)
                SettingsEnumPicker(String(localized: "Color profile", table: "Settings"),
                                   selection: $settings.saveColorProfile) { $0.settingsLabel }
            }
            Section(String(localized: "Metadata", table: "Settings")) {
                Toggle(String(localized: "Keep metadata (EXIF, IPTC)", table: "Settings"), isOn: $settings.saveKeepMetadata)
                Toggle(String(localized: "Remove location (GPS) information", table: "Settings"), isOn: $settings.saveStripGPS)
            }
            Section(String(localized: "Safety", table: "Settings")) {
                SettingsEnumPicker(String(localized: "Confirm before overwriting", table: "Settings"),
                                   selection: $settings.saveOverwriteConfirmation) { $0.settingsLabel }
                Toggle(String(localized: "Keep recovery copies of unsaved work", table: "Settings"),
                       isOn: $settings.saveAutoRecover)
            }
        }
    }
}
