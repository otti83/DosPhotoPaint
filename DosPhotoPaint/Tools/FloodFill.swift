import CoreGraphics
import Foundation

/// Pure flood-fill algorithm on raw 8-bit RGBA **premultiplied** bytes (rows top-first).
///
/// Pixels are compared in straight (un-premultiplied) RGBA including the alpha channel:
/// two pixels match when every channel differs by at most `tolerance`. Fully transparent
/// pixels are all treated as identical regardless of their hidden colour bytes.
nonisolated enum FloodFill {
    /// A copy of pixel data that can be sent to a background task.
    struct Bitmap: Sendable {
        var data: [UInt8]
        var width: Int
        var height: Int
        var bytesPerRow: Int
    }

    struct Result: Sendable {
        /// Coverage 0…255 per pixel for the whole bitmap (`width * height`, no row padding).
        var mask: [UInt8]
        var width: Int
        var height: Int
        /// Integral pixel rect containing every non-zero mask value.
        var bounds: CGRect
    }

    struct Options: Sendable {
        var tolerance: Int
        var contiguous: Bool
        /// Gives pixels 4-adjacent to the filled region that narrowly miss the tolerance a
        /// partial coverage, so antialiased edges do not keep a halo of the old colour.
        var edgeBlend: Bool
        init(tolerance: Int, contiguous: Bool, edgeBlend: Bool = false) {
            self.tolerance = min(max(tolerance, 0), 255)
            self.contiguous = contiguous
            self.edgeBlend = edgeBlend
        }
    }

    /// Width of the extra tolerance band (in channel units) used by the edge blend.
    static let edgeBand = 48

    /// Returns nil when the seed is outside the bitmap.
    static func fill(_ bitmap: Bitmap, seedX: Int, seedY: Int, options: Options) -> Result? {
        let w = bitmap.width, h = bitmap.height
        guard seedX >= 0, seedY >= 0, seedX < w, seedY < h,
              bitmap.data.count >= bitmap.bytesPerRow * (h - 1) + w * 4 else { return nil }
        var mask = [UInt8](repeating: 0, count: w * h)
        var minX = w, minY = h, maxX = -1, maxY = -1
        let tol = options.tolerance

        bitmap.data.withUnsafeBufferPointer { px in
            let bpr = bitmap.bytesPerRow
            let seed = straight(px, seedY * bpr + seedX * 4)

            @inline(__always) func distance(_ x: Int, _ y: Int) -> Int {
                let c = straight(px, y * bpr + x * 4)
                return max(abs(c.0 - seed.0), abs(c.1 - seed.1), abs(c.2 - seed.2), abs(c.3 - seed.3))
            }

            mask.withUnsafeMutableBufferPointer { m in
                if options.contiguous {
                    var stack: [(Int, Int)] = [(seedX, seedY)]
                    while let (sx, y) = stack.popLast() {
                        if m[y * w + sx] != 0 || distance(sx, y) > tol { continue }
                        var x1 = sx, x2 = sx
                        while x1 > 0, m[y * w + x1 - 1] == 0, distance(x1 - 1, y) <= tol { x1 -= 1 }
                        while x2 < w - 1, m[y * w + x2 + 1] == 0, distance(x2 + 1, y) <= tol { x2 += 1 }
                        for x in x1...x2 { m[y * w + x] = 255 }
                        minX = min(minX, x1); maxX = max(maxX, x2); minY = min(minY, y); maxY = max(maxY, y)
                        for ny in [y - 1, y + 1] where ny >= 0 && ny < h {
                            var inRun = false
                            for x in x1...x2 {
                                let ok = m[ny * w + x] == 0 && distance(x, ny) <= tol
                                if ok && !inRun { stack.append((x, ny)) }
                                inRun = ok
                            }
                        }
                    }
                } else {
                    for y in 0..<h {
                        for x in 0..<w where distance(x, y) <= tol {
                            m[y * w + x] = 255
                            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                        }
                    }
                }

                guard options.edgeBlend, maxX >= 0 else { return }
                // Partial coverage for near-miss pixels touching the region (full-coverage pixels
                // only count as neighbours, so blending never cascades).
                let x0 = max(minX - 1, 0), x1 = min(maxX + 1, w - 1)
                let y0 = max(minY - 1, 0), y1 = min(maxY + 1, h - 1)
                var blended: [(Int, UInt8)] = []
                for y in y0...y1 {
                    for x in x0...x1 where m[y * w + x] == 0 {
                        let touches = (x > 0 && m[y * w + x - 1] == 255) || (x < w - 1 && m[y * w + x + 1] == 255)
                            || (y > 0 && m[(y - 1) * w + x] == 255) || (y < h - 1 && m[(y + 1) * w + x] == 255)
                        guard touches else { continue }
                        let d = distance(x, y)
                        guard d > tol, d <= tol + edgeBand else { continue }
                        let cov = 255 * (edgeBand - (d - tol)) / (edgeBand + 1)
                        if cov > 0 { blended.append((y * w + x, UInt8(cov))) }
                    }
                }
                for (i, c) in blended {
                    m[i] = c
                    minX = min(minX, i % w); maxX = max(maxX, i % w); minY = min(minY, i / w); maxY = max(maxY, i / w)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return Result(mask: mask, width: w, height: h, bounds: rect)
    }

    /// Straight RGBA (0…255) of the pixel starting at byte `i`.
    @inline(__always)
    private static func straight(_ px: UnsafeBufferPointer<UInt8>, _ i: Int) -> (Int, Int, Int, Int) {
        let a = Int(px[i + 3])
        if a == 0 { return (0, 0, 0, 0) }
        if a == 255 { return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]), 255) }
        func un(_ c: UInt8) -> Int { min(255, (Int(c) * 255 + a / 2) / a) }
        return (un(px[i]), un(px[i + 1]), un(px[i + 2]), a)
    }
}
