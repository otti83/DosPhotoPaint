import SwiftUI

struct PerformanceSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsTabForm {
            Section {
                Picker(String(localized: "Preset", table: "Settings"), selection: $settings.performancePreset) {
                    ForEach(PerformancePreset.allCases) { Text($0.settingsLabel).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Choosing a preset sets the options below. You can adjust them individually afterwards.", tableName: "Settings")
            }
            Section(String(localized: "Details", table: "Settings")) {
                SettingsIntField(title: String(localized: "Image cache size", table: "Settings"),
                                 value: $settings.performanceCacheMB, range: AppSettings.cacheMBRange, step: 64, unit: "MB")
                Toggle(String(localized: "Preload neighboring images", table: "Settings"),
                       isOn: $settings.performancePreloadEnabled)
                SettingsIntField(title: String(localized: "Images to preload on each side", table: "Settings"),
                                 value: $settings.photoPreloadCount, range: AppSettings.preloadRange)
                    .disabled(!settings.performancePreloadEnabled)
                Toggle(String(localized: "High-quality scaling", table: "Settings"),
                       isOn: $settings.performanceHighQualityInterpolation)
                Toggle(String(localized: "Release cached images when memory is low", table: "Settings"),
                       isOn: $settings.performanceReleaseOnMemoryPressure)
            }
            Section {
                Text("A smaller cache size takes effect as new images are loaded.", tableName: "Settings")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
