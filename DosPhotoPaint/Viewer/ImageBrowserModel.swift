import AppKit
import Observation

/// One image in the Photo Mode browser.
nonisolated struct BrowserItem: Identifiable, Hashable, Sendable {
    let url: URL
    /// Folder relative to the browser root ("" for the root itself).
    let folder: String
    let fileSize: Int?
    let modified: Date?
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Lists the images of the current folder (optionally with its subfolders) for the image browser.
/// One per window. The root stays fixed while the user opens images in subfolders, and moves to
/// the current image's folder when that is outside the root.
@Observable
final class ImageBrowserModel {
    private(set) var items: [BrowserItem] = []
    private(set) var isLoading = false
    /// The folder could not be read (App Sandbox: folder access not granted yet).
    private(set) var accessDenied = false
    /// The listing stopped at `itemLimit` files.
    private(set) var isTruncated = false
    private(set) var rootFolder: URL?

    nonisolated static let itemLimit = 20_000

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Security-scoped access to the root kept while browsing, so files in subfolders can be opened.
    @ObservationIgnored nonisolated(unsafe) private var heldAccess: URL?

    deinit { heldAccess?.stopAccessingSecurityScopedResource() }

    /// Lists `session`'s images: the explicit file list, or the folder of the current image.
    func load(session: BrowsingSession, includeSubfolders: Bool, order: ImageSortOrder) {
        task?.cancel()
        if session.isExplicit {
            rootFolder = nil
            accessDenied = false
            isTruncated = false
            items = session.urls.map { Self.item(for: $0, root: nil) }
            isLoading = false
            return
        }
        guard let current = session.currentURL else {
            items = []
            return
        }
        let folder = current.deletingLastPathComponent().standardizedFileURL
        if let root = rootFolder, Self.contains(root, folder) {
            // Keep the root (the user opened an image in one of its subfolders).
        } else {
            rootFolder = folder
        }
        guard let root = rootFolder else { return }
        heldAccess?.stopAccessingSecurityScopedResource()
        heldAccess = FolderAccess.startAccessing(root)
        isLoading = true
        task = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.list(root: root, recursive: includeSubfolders, order: order, limit: Self.itemLimit)
            }.value
            guard let self, !Task.isCancelled, self.rootFolder == root else { return }
            self.isLoading = false
            if let result {
                self.accessDenied = false
                self.items = result.items
                self.isTruncated = result.truncated
            } else {
                self.accessDenied = true
                self.isTruncated = false
                // At least the image being shown.
                self.items = [Self.item(for: current, root: root)]
            }
        }
    }

    func cancel() {
        task?.cancel()
        isLoading = false
    }

    // MARK: - Listing (thread-safe)

    nonisolated static func contains(_ root: URL, _ folder: URL) -> Bool {
        let r = root.standardizedFileURL.path, f = folder.standardizedFileURL.path
        return f == r || f.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }

    nonisolated static func item(for url: URL, root: URL?) -> BrowserItem {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var folder = ""
        if let root {
            let parent = url.deletingLastPathComponent().standardizedFileURL.path
            let r = root.standardizedFileURL.path
            if parent != r, parent.hasPrefix(r) {
                folder = String(parent.dropFirst(r.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        } else {
            folder = url.deletingLastPathComponent().lastPathComponent
        }
        return BrowserItem(url: url.standardizedFileURL, folder: folder, fileSize: v?.fileSize, modified: v?.contentModificationDate)
    }

    /// Readable images under `root` (hidden files and packages skipped), sorted folder by folder
    /// (root first, subfolders in natural order) and by `order` inside each folder. Nil when the
    /// root cannot be read.
    nonisolated static func list(root: URL, recursive: Bool, order: ImageSortOrder, limit: Int) -> (items: [BrowserItem], truncated: Bool)? {
        var urls: [URL]
        var truncated = false
        if recursive {
            let keys: [URLResourceKey] = [.contentTypeKey, .isRegularFileKey]
            guard (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil,
                  let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { return nil }
            urls = []
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let type = v.contentType, ImageTypes.isReadableImage(type) else { continue }
                urls.append(url.standardizedFileURL)
                if urls.count >= limit { truncated = true; break }
            }
        } else {
            guard let listed = BrowsingSession.listImages(in: root, order: order) else { return nil }
            urls = Array(listed.prefix(limit))
            truncated = listed.count > limit
        }
        let groups = Dictionary(grouping: urls) { $0.deletingLastPathComponent().standardizedFileURL.path }
        let rootPath = root.standardizedFileURL.path
        let folderOrder = groups.keys.sorted { a, b in
            if a == rootPath { return b != rootPath }
            if b == rootPath { return false }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        let sortedURLs = folderOrder.flatMap { BrowsingSession.sorted(groups[$0] ?? [], by: order) }
        return (sortedURLs.map { item(for: $0, root: root) }, truncated)
    }
}

/// Small in-memory thumbnail cache for the browser (decoded off the main thread).
final class BrowserThumbnails {
    static let shared = BrowserThumbnails()
    private let cache = NSCache<NSURL, CGImage>()

    init() {
        cache.countLimit = 3000
        cache.totalCostLimit = 384 * 1024 * 1024   // bytes of decoded thumbnails
    }

    func cached(_ url: URL) -> CGImage? { cache.object(forKey: url as NSURL) }

    func thumbnail(for url: URL, maxPixelSize: Int) async -> CGImage? {
        if let hit = cached(url) { return hit }
        let image = await Task.detached(priority: .utility) {
            try? ImageLoader.loadDisplayImage(url: url, maxPixelSize: maxPixelSize)
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height) }
        return image
    }
}
