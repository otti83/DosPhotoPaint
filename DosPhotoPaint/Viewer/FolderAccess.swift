import AppKit

/// Security-scoped folder bookmarks so Photo Mode can browse sibling files under the App Sandbox.
///
/// A file opened from Finder grants access to that file only. To browse its folder the user
/// grants access once via an Open panel ("Allow Access to Folder…"); the bookmark is stored and
/// reused on later launches.
nonisolated enum FolderAccess {
    private static let defaultsKey = "folderAccess.bookmarks"

    /// Starts accessing a stored bookmark covering `folder`. Returns the URL to stop later.
    static func startAccessing(_ folder: URL) -> URL? {
        guard let stored = AppRuntime.defaults.dictionary(forKey: defaultsKey) as? [String: Data] else { return nil }
        let path = folder.standardizedFileURL.path
        // Exact folder or an ancestor that was granted.
        let candidates = stored.keys.filter { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        for key in candidates.sorted(by: { $0.count > $1.count }) {
            guard let data = stored[key] else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else {
                remove(path: key)
                continue
            }
            if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                store(fresh, for: key)
            }
            if url.startAccessingSecurityScopedResource() { return url }
        }
        return nil
    }

    /// Persists access to a folder the user picked in an Open panel.
    static func remember(_ folder: URL) {
        guard let data = try? folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        store(data, for: folder.standardizedFileURL.path)
    }

    private static func store(_ data: Data, for path: String) {
        var stored = (AppRuntime.defaults.dictionary(forKey: defaultsKey) as? [String: Data]) ?? [:]
        stored[path] = data
        AppRuntime.defaults.set(stored, forKey: defaultsKey)
    }

    private static func remove(path: String) {
        var stored = (AppRuntime.defaults.dictionary(forKey: defaultsKey) as? [String: Data]) ?? [:]
        stored.removeValue(forKey: path)
        AppRuntime.defaults.set(stored, forKey: defaultsKey)
    }
}
