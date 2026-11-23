import SwiftUI

/// Preferences window content (⌘,): one tab per settings category.
struct SettingsView: View {
    @Bindable var selection: SettingsSelection
    @Bindable var settings = AppSettings.shared
    @State private var confirmRestore = false
    @State private var offerRelaunch = false

    var body: some View {
        // A fixed sidebar (always visible, no collapse button) + the selected category on the right.
        // A TabView with seven tabs overflowed into a "»" menu on recent macOS, and a
        // NavigationSplitView adds a sidebar toggle that hides the categories.
        HStack(spacing: 0) {
            List(selection: sidebarSelection) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .padding(.vertical, 2)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Divider()
            VStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if selection.tab != .shortcuts {
                    Divider()
                    HStack {
                        Spacer()
                        Button(String(localized: "Restore Defaults…", table: "Settings")) { confirmRestore = true }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .confirmationDialog(String(localized: "Restore all settings to their defaults?", table: "Settings"),
                            isPresented: $confirmRestore, titleVisibility: .visible) {
            Button(String(localized: "Restore Defaults", table: "Settings"), role: .destructive) {
                let oldLanguage = settings.language
                settings.resetToDefaults()
                if settings.language != oldLanguage { offerRelaunch = true }
            }
            Button(String(localized: "Cancel", table: "Settings"), role: .cancel) {}
        } message: {
            Text("This does not affect your documents.", tableName: "Settings")
        }
        .alert(String(localized: "Relaunch to change the language?", table: "Settings"), isPresented: $offerRelaunch) {
            Button(String(localized: "Relaunch Now", table: "Settings")) { AppRelauncher.relaunch() }
            Button(String(localized: "Later", table: "Settings"), role: .cancel) {}
        } message: {
            Text("The new language is used after DosPhotoPaint restarts. You will be asked to save any unsaved documents first.", tableName: "Settings")
        }
    }

    /// `List` selection needs an optional binding; a deselect (click on empty space) keeps the current tab.
    private var sidebarSelection: Binding<SettingsTab?> {
        Binding(get: { selection.tab }, set: { if let tab = $0 { selection.tab = tab } })
    }

    @ViewBuilder private var detail: some View {
        switch selection.tab {
        case .general: GeneralSettingsView(settings: settings, languageChanged: { offerRelaunch = true })
        case .photo: PhotoSettingsView(settings: settings)
        case .paint: PaintSettingsView(settings: settings)
        case .save: SaveSettingsView(settings: settings)
        case .slideshow: SlideshowSettingsView(settings: settings)
        case .performance: PerformanceSettingsView(settings: settings)
        case .shortcuts: ShortcutsSettingsView()
        }
    }
}

extension SettingsTab {
    var title: String {
        switch self {
        case .general: String(localized: "General", table: "Settings")
        case .photo: String(localized: "Photo", table: "Settings")
        case .paint: String(localized: "Paint", table: "Settings")
        case .save: String(localized: "Save", table: "Settings")
        case .slideshow: String(localized: "Slideshow", table: "Settings")
        case .performance: String(localized: "Performance", table: "Settings")
        case .shortcuts: String(localized: "Shortcuts", table: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .photo: "photo"
        case .paint: "paintbrush"
        case .save: "square.and.arrow.down"
        case .slideshow: "play.rectangle"
        case .performance: "gauge.with.dots.needle.67percent"
        case .shortcuts: "keyboard"
        }
    }
}
