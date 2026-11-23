import Foundation
import Observation

/// Ordered list of images a Photo window can step through, plus the current position.
///
/// - Explicit session: exactly the files the user selected in Finder (multi-selection).
/// - Folder session: every readable image in the folder of the current file, re-listed when
///   the user moves to a file in another folder.
@Observable
final class BrowsingSession {
    private(set) var urls: [URL] = []
    private(set) var currentIndex: Int?
    private(set) var isExplicit: Bool
    private(set) var folderURL: URL?
    /// True when the folder could not be listed (typically the App Sandbox: only the opened file
    /// is accessible until the user grants folder access).
    private(set) var folderAccessDenied = false
    /// Called after `urls` changed asynchronously (folder listing finished).
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var listingTask: Task<Void, Never>?
    /// Security-scoped access to `folderURL` kept open while the folder is browsed, so sibling
    /// files can be opened under the App Sandbox (not only listed).
    @ObservationIgnored nonisolated(unsafe) private var heldAccess: URL?
    @ObservationIgnored private var heldAccessFolder: URL?

    deinit { heldAccess?.stopAccessingSecurityScopedResource() }

    init(explicitURLs: [URL]?) {
        if let explicitURLs, explicitURLs.count > 1 {
            urls = explicitURLs.map(\.standardizedFileURL)
            isExplicit = true
        } else {
            isExplicit = false
        }
    }

    var currentURL: URL? { currentIndex.flatMap { urls.indices.contains($0) ? urls[$0] : nil } }

    /// 1-based position and total.
    var position: (index: Int, count: Int)? {
        guard let i = currentIndex, !urls.isEmpty else { return nil }
        return (i + 1, urls.count)
    }

    /// Records that `url` is displayed; lists its folder if needed.
    func didShow(_ url: URL) {
        let url = url.standardizedFileURL
        if let i = urls.firstIndex(of: url) {
            currentIndex = i
            if !isExplicit, folderURL != url.deletingLastPathComponent() { listFolder(of: url) }
            return
        }
        if isExplicit {
            urls.append(url)
            currentIndex = urls.count - 1
            return
        }
        urls = [url]
        currentIndex = 0
        listFolder(of: url)
    }

    func url(at index: Int) -> URL? { urls.indices.contains(index) ? urls[index] : nil }

    func url(movingBy delta: Int, loop: Bool) -> URL? {
        guard let i = currentIndex, !urls.isEmpty else { return nil }
        var j = i + delta
        if loop { j = ((j % urls.count) + urls.count) % urls.count }
        guard urls.indices.contains(j), j != i else { return nil }
        return urls[j]
    }

    func replace(with newURLs: [URL], current: URL?) {
        listingTask?.cancel()
        urls = newURLs.map(\.standardizedFileURL)
        isExplicit = newURLs.count > 1
        folderURL = nil
        folderAccessDenied = false
        currentIndex = current.flatMap { urls.firstIndex(of: $0.standardizedFileURL) } ?? (urls.isEmpty ? nil : 0)
        onChange?()
    }

    /// Removes a file that disappeared from disk. Returns the URL to show instead, if any.
    func remove(_ url: URL) -> URL? {
        guard let i = urls.firstIndex(of: url.standardizedFileURL) else { return currentURL }
        urls.remove(at: i)
        if urls.isEmpty { currentIndex = nil; return nil }
        let next = min(i, urls.count - 1)
        if currentIndex == i { currentIndex = next } else if let c = currentIndex, c > i { currentIndex = c - 1 }
        onChange?()
        return currentURL
    }

    /// Re-sorts with the current sort order (keeps the current file).
    func resort() {
        let current = currentURL
        urls = Self.sorted(urls, by: AppSettings.shared.photoSortOrder)
        currentIndex = current.flatMap { urls.firstIndex(of: $0) }
        onChange?()
    }

    /// Re-lists the folder (after access was granted or the sort order changed).
    func reloadFolder() {
        guard !isExplicit, let url = currentURL else { return }
        listFolder(of: url)
    }

    private func listFolder(of url: URL) {
        guard AppSettings.shared.photoFolderNavigation else { return }
        let folder = url.deletingLastPathComponent()
        folderURL = folder
        let order = AppSettings.shared.photoSortOrder
        if heldAccess == nil || heldAccessFolder != folder {
            heldAccess?.stopAccessingSecurityScopedResource()
            heldAccess = FolderAccess.startAccessing(folder)
            heldAccessFolder = folder
        }
        listingTask?.cancel()
        listingTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> [URL]? in
                Self.listImages(in: folder, order: order)
            }.value
            guard let self, !Task.isCancelled, self.folderURL == folder, let current = self.currentURL else { return }
            guard let result, !result.isEmpty else {
                self.folderAccessDenied = true
                self.onChange?()
                return
            }
            self.folderAccessDenied = false
            self.urls = result.contains(current) ? result : Self.sorted(result + [current], by: order)
            self.currentIndex = self.urls.firstIndex(of: current)
            self.onChange?()
        }
    }

    // MARK: - Listing & sorting (thread-safe)

    /// Readable images in `folder` (non-recursive, hidden files skipped), or nil if unreadable.
    nonisolated static func listImages(in folder: URL, order: ImageSortOrder) -> [URL]? {
        let keys: [URLResourceKey] = [.contentTypeKey, .isRegularFileKey, .contentModificationDateKey, .creationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return nil }
        let images = items.filter { url in
            guard let v = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey]),
                  v.isRegularFile == true, let type = v.contentType else { return false }
            return ImageTypes.isReadableImage(type)
        }
        return sorted(images.map(\.standardizedFileURL), by: order)
    }

    nonisolated static func sorted(_ urls: [URL], by order: ImageSortOrder) -> [URL] {
        switch order {
        case .naturalName:
            return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        case .name:
            return urls.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: [.caseInsensitive]) == .orderedAscending }
        case .modificationDate, .creationDate:
            let key: URLResourceKey = order == .modificationDate ? .contentModificationDateKey : .creationDateKey
            let dates = Dictionary(urls.map { url in
                (url, (try? url.resourceValues(forKeys: [key])).flatMap { order == .modificationDate ? $0.contentModificationDate : $0.creationDate } ?? .distantPast)
            }, uniquingKeysWith: { a, _ in a })
            return urls.sorted {
                let a = dates[$0]!, b = dates[$1]!
                return a == b ? $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending : a < b
            }
        }
    }
}
