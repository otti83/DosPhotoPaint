import CoreGraphics
import Foundation

/// LRU cache of downsampled display images, cost-limited by bytes, purged on memory pressure.
/// In-flight decodes are shared so a preload and a display request never decode twice.
final class ImageCache {
    static let shared = ImageCache()

    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let cache = NSCache<NSString, Entry>()
    private var inFlight: [String: Task<CGImage, Error>] = [:]
    private var prefetchTasks: [String: Task<Void, Never>] = [:]
    private var pressureSource: DispatchSourceMemoryPressure?

    init() {
        cache.totalCostLimit = AppSettings.shared.effectiveCacheBytes
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard AppSettings.shared.performanceReleaseOnMemoryPressure else { return }
                self?.removeAll()
            }
        }
        source.resume()
        pressureSource = source
    }

    private func key(_ url: URL, _ maxPixelSize: Int) -> String { "\(url.standardizedFileURL.path)#\(maxPixelSize)" }

    func cachedImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        cache.object(forKey: key(url, maxPixelSize) as NSString)?.image
    }

    /// Returns a display image (decoding off the main thread if not cached).
    func displayImage(for url: URL, maxPixelSize: Int, priority: TaskPriority = .userInitiated) async throws -> CGImage {
        let k = key(url, maxPixelSize)
        if let hit = cache.object(forKey: k as NSString) { return hit.image }
        if let task = inFlight[k] { return try await task.value }
        let task = Task.detached(priority: priority) {
            try ImageLoader.loadDisplayImage(url: url, maxPixelSize: maxPixelSize)
        }
        inFlight[k] = task
        defer { inFlight[k] = nil }
        let image = try await task.value
        cache.totalCostLimit = AppSettings.shared.effectiveCacheBytes
        cache.setObject(Entry(image), forKey: k as NSString, cost: image.bytesPerRow * image.height)
        return image
    }

    /// Starts decoding in the background without waiting (used for preloading neighbours).
    /// A short delay lets `cancelPrefetch` drop requests made stale by fast navigation
    /// (e.g. holding the arrow key) before any decoding work starts.
    func prefetch(_ url: URL, maxPixelSize: Int) {
        let k = key(url, maxPixelSize)
        guard cache.object(forKey: k as NSString) == nil, inFlight[k] == nil, prefetchTasks[k] == nil else { return }
        prefetchTasks[k] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            _ = try? await self?.displayImage(for: url, maxPixelSize: maxPixelSize, priority: .utility)
            self?.prefetchTasks[k] = nil
        }
    }

    /// Cancels queued prefetches (not yet decoding) that are not in `keep`. Decodes already
    /// running and display requests are never affected, so other windows keep working.
    func cancelPrefetch(except keep: Set<URL>, maxPixelSize: Int) {
        let keepKeys = Set(keep.map { key($0, maxPixelSize) })
        for (k, task) in prefetchTasks where !keepKeys.contains(k) {
            task.cancel()
            prefetchTasks[k] = nil
        }
    }

    func remove(_ url: URL) {
        // NSCache has no enumeration; entries for a changed file are keyed by path+size,
        // so evict the common budgets explicitly.
        for size in [256, 512, 1024, 2048, 4096, 8192] { cache.removeObject(forKey: key(url, size) as NSString) }
    }

    func removeAll() { cache.removeAllObjects() }
}
