import Foundation

/// Random slideshow order: every image is shown once per round; a new round starts (if looping)
/// when all were shown. Pure value type so it can be unit tested with a seeded generator.
nonisolated struct SlideshowShuffle: Sendable {
    private var queue: [URL] = []
    private var played: Set<URL> = []

    init(current: URL?) {
        if let current { played.insert(current) }
    }

    /// Next image to show, or nil when the round is over and `loop` is false.
    /// `all` is the live session list (images may have been added or removed meanwhile).
    mutating func next(all: [URL], current: URL?, loop: Bool, using generator: inout some RandomNumberGenerator) -> URL? {
        let live = Set(all)
        queue.removeAll { !live.contains($0) }
        if queue.isEmpty {
            var candidates = all.filter { !played.contains($0) }
            if candidates.isEmpty {
                guard loop else { return nil }
                played = current.map { [$0] } ?? []
                candidates = all.filter { !played.contains($0) }
                guard !candidates.isEmpty else { return nil }
            }
            queue = candidates.shuffled(using: &generator)
        }
        let url = queue.removeFirst()
        played.insert(url)
        return url
    }
}
