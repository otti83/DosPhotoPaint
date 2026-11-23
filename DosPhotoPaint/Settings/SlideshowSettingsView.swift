import SwiftUI

struct SlideshowSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsTabForm {
            Section(String(localized: "Playback", table: "Settings")) {
                LabeledContent(String(localized: "Interval", table: "Settings")) {
                    HStack(spacing: 6) {
                        TextField(String(localized: "Interval", table: "Settings"), value: intervalBinding, format: .number.precision(.fractionLength(0...1)))
                            .labelsHidden().multilineTextAlignment(.trailing).frame(width: 70)
                        Stepper(String(localized: "Interval", table: "Settings"), value: intervalBinding,
                                in: AppSettings.slideshowIntervalRange, step: 1).labelsHidden()
                        Text("seconds", tableName: "Settings").foregroundStyle(.secondary)
                    }
                }
                Toggle(String(localized: "Loop", table: "Settings"), isOn: $settings.slideshowLoop)
                Toggle(String(localized: "Shuffle", table: "Settings"), isOn: $settings.slideshowShuffle)
            }
            Section(String(localized: "Display", table: "Settings")) {
                Toggle(String(localized: "Start in full screen", table: "Settings"), isOn: $settings.slideshowFullScreen)
                SettingsEnumPicker(String(localized: "Image size", table: "Settings"),
                                   selection: $settings.slideshowFit) { $0.settingsLabel }
                SettingsEnumPicker(String(localized: "Transition", table: "Settings"),
                                   selection: $settings.slideshowTransition) { $0.settingsLabel }
            }
        }
    }

    private var intervalBinding: Binding<Double> {
        let r = AppSettings.slideshowIntervalRange
        return Binding(get: { min(max(settings.slideshowInterval, r.lowerBound), r.upperBound) },
                       set: { settings.slideshowInterval = min(max($0, r.lowerBound), r.upperBound) })
    }
}
