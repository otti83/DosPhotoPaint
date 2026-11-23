import Foundation

/// Prefetches the neighbours of the current image into `ImageCache` so stepping through a
/// folder feels instant. Never decodes more than `count` images on each side.
final class ImagePreloader {
    /// URLs to prefetch for a session position: next/previous alternating, nearest first.
    static func neighbours(of index: Int, in urls: [URL], count: Int, loop: Bool) -> [URL] {
        guard count > 0, urls.indices.contains(index), urls.count > 1 else { return [] }
        var result: [URL] = []
        var seen: Set<Int> = [index]
        for d in 1...count {
            for j in [index + d, index - d] {
                let k = loop ? ((j % urls.count) + urls.count) % urls.count : j
                guard urls.indices.contains(k), seen.insert(k).inserted else { continue }
                result.append(urls[k])
            }
        }
        return result
    }

    /// Call after every navigation / session change.
    func update(session: BrowsingSession, maxPixelSize: Int) {
        let settings = AppSettings.shared
        let cache = ImageCache.shared
        guard let index = session.currentIndex, let current = session.currentURL else { return }
        let wanted = Self.neighbours(of: index, in: session.urls, count: settings.effectivePreloadCount,
                                     loop: settings.photoLoopNavigation)
        cache.cancelPrefetch(except: Set(wanted + [current]), maxPixelSize: maxPixelSize)
        for url in wanted { cache.prefetch(url, maxPixelSize: maxPixelSize) }
    }
}
