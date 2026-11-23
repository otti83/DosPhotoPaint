import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    /// Called after the language setting changed (to offer a relaunch).
    var languageChanged: () -> Void
    @State private var hasFullDiskAccess = FileAccess.hasFullDiskAccess

    var body: some View {
        SettingsTabForm {
            Section {
                Picker(String(localized: "Language", table: "Settings"), selection: languageBinding) {
                    ForEach(AppLanguageSetting.allCases) { Text($0.settingsLabel).tag($0) }
                }
                SettingsEnumPicker(String(localized: "Appearance", table: "Settings"),
                                   selection: $settings.appearance) { $0.settingsLabel }
            } footer: {
                Text("A language change takes effect after relaunching the app.", tableName: "Settings")
            }
            Section(String(localized: "Startup", table: "Settings")) {
                SettingsEnumPicker(String(localized: "When no file is opened", table: "Settings"),
                                   selection: $settings.startupMode) { $0.settingsLabel }
                Toggle(String(localized: "Reopen windows at launch", table: "Settings"), isOn: $settings.restoreWindows)
            }
            Section(String(localized: "Windows", table: "Settings")) {
                Toggle(String(localized: "Show toolbar", table: "Settings"), isOn: $settings.showToolbar)
                Toggle(String(localized: "Show status bar", table: "Settings"), isOn: $settings.showStatusBar)
                Toggle(String(localized: "Ask before closing a document with unsaved changes", table: "Settings"),
                       isOn: $settings.confirmUnsavedOnClose)
            }
            Section {
                LabeledContent(String(localized: "Full Disk Access", table: "Settings")) {
                    HStack(spacing: 8) {
                        Text(hasFullDiskAccess ? String(localized: "Allowed", table: "Settings")
                                               : String(localized: "Not allowed", table: "Settings"))
                            .foregroundStyle(hasFullDiskAccess ? Color.secondary : Color.orange)
                        Button(String(localized: "Open System Settings…", table: "Settings")) {
                            FileAccess.openFullDiskAccessSettings()
                        }
                    }
                }
            } header: {
                Text("File Access", tableName: "Settings")
            } footer: {
                Text("With Full Disk Access, macOS never asks before DosPhotoPaint opens images on the Desktop, in Documents, Downloads or on network and external drives. Relaunch the app after changing it.", tableName: "Settings")
            }
            Section(String(localized: "Recent Items", table: "Settings")) {
                SettingsIntField(title: String(localized: "Number of recent documents", table: "Settings"),
                                 value: $settings.recentDocumentsLimit, range: AppSettings.recentDocumentsRange)
            }
        }
        // Re-check when the user comes back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = FileAccess.hasFullDiskAccess
        }
    }

    private var languageBinding: Binding<AppLanguageSetting> {
        Binding(get: { settings.language },
                set: { new in
                    guard new != settings.language else { return }
                    settings.language = new
                    languageChanged()
                })
    }
}
