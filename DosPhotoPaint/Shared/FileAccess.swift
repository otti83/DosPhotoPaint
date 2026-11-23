import AppKit

/// File-system access outside the App Sandbox (the app is distributed with Developer ID and is
/// not sandboxed since 0.1.0): Full Disk Access status and guidance.
nonisolated enum FileAccess {

    // MARK: Full Disk Access

    /// Whether the user granted Full Disk Access (System Settings ▸ Privacy & Security). Without
    /// it macOS asks once per protected location (Desktop, Documents, Downloads, network and
    /// removable volumes); with it, never. Probed by opening a file only readable with that grant.
    static var hasFullDiskAccess: Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = try? FileHandle(forReadingFrom: probe) else { return false }
        try? handle.close()
        return true
    }

    /// Opens System Settings at Privacy & Security ▸ Full Disk Access.
    @MainActor static func openFullDiskAccessSettings() {
        let urls = ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    private static let askedKey = "onboarding.fullDiskAccessAsked"

    /// First launch only: explains Full Disk Access and offers to open System Settings.
    /// Not shown when access is already granted, and never again after the first time.
    @MainActor static func offerFullDiskAccessOnFirstLaunch() {
        let defaults = AppRuntime.defaults
        guard !AppRuntime.isUnitTestHost, !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)
        guard !hasFullDiskAccess else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Allow Full Disk Access?", table: "Settings")
        alert.informativeText = String(localized: "DosPhotoPaint opens and browses images wherever they are. Without Full Disk Access, macOS asks once for each protected location (Desktop, Documents, Downloads, network and external drives). With it, you are never asked.\n\nIn System Settings, turn on DosPhotoPaint under Full Disk Access, then relaunch the app. You can do this later from Settings ▸ General.", table: "Settings")
        alert.addButton(withTitle: String(localized: "Open System Settings", table: "Settings"))
        alert.addButton(withTitle: String(localized: "Later", table: "Settings"))
        if alert.runModal() == .alertFirstButtonReturn { openFullDiskAccessSettings() }
    }
}
