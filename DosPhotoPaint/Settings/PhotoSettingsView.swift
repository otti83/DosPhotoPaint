import SwiftUI

struct PhotoSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsTabForm {
            Section(String(localized: "Display", table: "Settings")) {
                SettingsEnumPicker(String(localized: "Initial zoom", table: "Settings"),
                                   selection: $settings.photoInitialZoom) { $0.settingsLabel }
                SettingsEnumPicker(String(localized: "When switching images", table: "Settings"),
                                   selection: $settings.photoZoomOnNavigate) { $0.settingsLabel }
                SettingsEnumPicker(String(localized: "Scaling", table: "Settings"),
                                   selection: $settings.photoInterpolation) { $0.settingsLabel }
                SettingsEnumPicker(String(localized: "Background", table: "Settings"),
                                   selection: $settings.photoBackground) { $0.settingsLabel }
                Toggle(String(localized: "Show checkerboard behind transparency", table: "Settings"),
                       isOn: $settings.photoCheckerboard)
                Toggle(String(localized: "Play animated GIFs automatically", table: "Settings"),
                       isOn: $settings.photoAutoplayGIF)
            }
            Section(String(localized: "Mouse and Trackpad", table: "Settings")) {
                SettingsEnumPicker(String(localized: "Scroll wheel", table: "Settings"),
                                   selection: $settings.photoWheel) { $0.settingsLabel }
                SettingsEnumPicker(String(localized: "Command + scroll wheel", table: "Settings"),
                                   selection: $settings.photoCommandWheel) { $0.settingsLabel }
                Toggle(String(localized: "Zoom around the pointer", table: "Settings"), isOn: $settings.photoZoomAtCursor)
                SettingsEnumPicker(String(localized: "Double-click", table: "Settings"),
                                   selection: $settings.photoDoubleClick) { $0.settingsLabel }
            }
            Section(String(localized: "Browsing", table: "Settings")) {
                Toggle(String(localized: "Browse other images in the same folder", table: "Settings"),
                       isOn: $settings.photoFolderNavigation)
                SettingsEnumPicker(String(localized: "Sort by", table: "Settings"),
                                   selection: $settings.photoSortOrder) { $0.settingsLabel }
                Toggle(String(localized: "Loop at the first and last image", table: "Settings"),
                       isOn: $settings.photoLoopNavigation)
            }
        }
    }
}
