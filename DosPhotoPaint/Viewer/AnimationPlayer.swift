import AppKit
import ImageIO
import Observation

/// Plays animated images (GIF, APNG, animated WebP/HEICS) frame by frame and always loops,
/// regardless of the loop count stored in the file (a "play once" GIF would otherwise stop on its
/// last frame, which is often empty). Image I/O returns each frame fully composited at canvas
/// size, so a frame can be shown on its own (the frame strip jumps to any frame).
///
/// Frames are decoded off the main thread at display size and cached while they fit in a memory
/// budget; larger animations are decoded on the fly.
@Observable
final class AnimationPlayer {
    /// Frames of the loaded animation (0 when nothing is loaded).
    private(set) var frameCount = 0
    private(set) var currentFrame = 0
    private(set) var isPaused = false
    @ObservationIgnored private(set) var playingURL: URL?

    /// An animation is loaded (playing or paused): the shown image is a frame, not the still preview.
    var isPlaying: Bool { playingURL != nil }

    @ObservationIgnored private var source: CGImageSource?
    @ObservationIgnored private var delays: [Double] = []
    @ObservationIgnored private var maxPixelSize = 0
    @ObservationIgnored private var cache: [Int: CGImage] = [:]
    @ObservationIgnored private var cacheAllowed = true
    @ObservationIgnored private var onFrame: ((CGImage) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// Memory for cached frames of one animation.
    nonisolated static let cacheBudgetBytes = 256 * 1024 * 1024
    /// Browsers treat delays below 20 ms as 100 ms; so do we (many GIFs rely on it).
    nonisolated static func normalizedDelay(_ d: Double?) -> Double {
        guard let d, d.isFinite, d >= 0.02 else { return 0.1 }
        return d
    }

    /// Loads `url` and starts looping. `onFrame` receives every frame to show (main thread).
    func play(url: URL, maxPixelSize: Int, onFrame: @escaping (CGImage) -> Void) {
        stop()
        generation += 1
        let gen = generation
        playingURL = url
        self.onFrame = onFrame
        self.maxPixelSize = maxPixelSize
        task = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { () -> (SourceBox, [Double], Int, Int)? in
                guard let src = try? ImageLoader.makeSource(url) else { return nil }
                let n = CGImageSourceGetCount(src)
                guard n > 1 else { return nil }
                let delays = (0..<n).map { Self.normalizedDelay(Self.frameDelay(src, $0)) }
                let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
                let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
                let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
                return (SourceBox(src), delays, w, h)
            }.value
            guard let self, self.generation == gen, let (box, delays, w, h) = loaded else { return }
            self.source = box.source
            self.delays = delays
            self.frameCount = delays.count
            self.currentFrame = 0
            let longest = max(min(max(w, h), maxPixelSize), 1)
            let scale = Double(longest) / Double(max(w, h, 1))
            let frameBytes = Int(Double(w) * scale) * Int(Double(h) * scale) * 4
            self.cacheAllowed = frameBytes * delays.count <= Self.cacheBudgetBytes
            await self.runLoop(gen: gen)
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        playingURL = nil
        source = nil
        delays = []
        cache = [:]
        onFrame = nil
        frameCount = 0
        currentFrame = 0
        isPaused = false
    }

    func togglePause() {
        guard isPlaying else { return }
        isPaused ? resume() : pause()
    }

    func pause() {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        task?.cancel()
        task = nil
    }

    func resume() {
        guard isPlaying, isPaused, source != nil else { return }
        isPaused = false
        let gen = generation
        task = Task { [weak self] in
            guard let self else { return }
            self.currentFrame = (self.currentFrame + 1) % max(self.frameCount, 1)
            await self.runLoop(gen: gen)
        }
    }

    /// Pauses and shows `index` (frame strip click).
    func show(frame index: Int) {
        guard isPlaying, frameCount > 0 else { return }
        pause()
        let i = min(max(index, 0), frameCount - 1)
        currentFrame = i
        let gen = generation
        Task { [weak self] in
            guard let self, let image = await self.frame(i), self.generation == gen, self.currentFrame == i else { return }
            self.onFrame?(image)
        }
    }

    func step(by delta: Int) {
        guard frameCount > 0 else { return }
        show(frame: ((currentFrame + delta) % frameCount + frameCount) % frameCount)
    }

    // MARK: - Playback

    private func runLoop(gen: Int) async {
        while !Task.isCancelled, generation == gen, !isPaused, frameCount > 0 {
            let i = currentFrame
            let started = ContinuousClock.now
            guard let image = await frame(i) else { return }
            guard !Task.isCancelled, generation == gen, !isPaused else { return }
            onFrame?(image)
            // The delay counts from when the frame was requested, so slow decodes do not stretch it.
            let deadline = started + .milliseconds(Int(delays[i] * 1000))
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, generation == gen, !isPaused else { return }
            currentFrame = (i + 1) % frameCount
        }
    }

    private func frame(_ i: Int) async -> CGImage? {
        if let hit = cache[i] { return hit }
        guard let src = source else { return nil }
        let size = maxPixelSize
        let box = SourceBox(src)
        let image = await Task.detached(priority: .userInitiated) { Self.decode(box.source, i, maxPixelSize: size) }.value
        if let image, cacheAllowed, source === src { cache[i] = image }
        return image
    }

    nonisolated fileprivate struct SourceBox: @unchecked Sendable {   // CGImageSource is thread-safe for reads
        let source: CGImageSource
        init(_ s: CGImageSource) { source = s }
    }

    nonisolated static func decode(_ src: CGImageSource, _ i: Int, maxPixelSize: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, i, opts as CFDictionary)
    }

    /// Frame delay in seconds from the format's dictionary (unclamped value preferred).
    nonisolated static func frameDelay(_ src: CGImageSource, _ i: Int) -> Double? {
        guard let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] else { return nil }
        let pairs: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        ]
        for (dict, unclamped, clamped) in pairs {
            guard let d = p[dict] as? [CFString: Any] else { continue }
            if let v = (d[unclamped] as? NSNumber)?.doubleValue, v > 0 { return v }
            if let v = (d[clamped] as? NSNumber)?.doubleValue { return v }
        }
        return nil
    }
}
