import AppKit

extension NSColor {
    /// Creates a colour from `#RRGGBB` or `#RRGGBBAA` (sRGB).
    convenience init?(hexRGBA: String) {
        var s = hexRGBA.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: UInt64
        if s.count == 6 { r = (v >> 16) & 0xff; g = (v >> 8) & 0xff; b = v & 0xff; a = 0xff }
        else { r = (v >> 24) & 0xff; g = (v >> 16) & 0xff; b = (v >> 8) & 0xff; a = v & 0xff }
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    /// `#RRGGBBAA` in sRGB.
    var hexRGBA: String {
        let c = usingColorSpace(.sRGB) ?? .black
        func byte(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent), byte(c.alphaComponent))
    }

    /// `#RRGGBB` in sRGB (no alpha).
    var hexRGB: String { String(hexRGBA.prefix(7)) }
}
