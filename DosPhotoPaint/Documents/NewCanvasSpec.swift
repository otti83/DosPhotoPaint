import AppKit

/// Parameters of a new blank canvas (File > New Canvas dialog). Pure value type: validation and
/// clamping live here so they can be tested without UI.
struct NewCanvasSpec: Equatable {
    enum Background: Equatable {
        case white
        case secondary
        case transparent
        case custom(NSColor)
    }

    var width: Int
    var height: Int
    var background: Background

    /// Defaults from the Paint settings (also what an automatically created untitled canvas uses).
    static func settingsDefault(_ s: AppSettings = .shared) -> NewCanvasSpec {
        let background: Background
        if s.paintTransparentBackground {
            background = .transparent
        } else if s.paintDefaultBackground.usingColorSpace(.sRGB)?.hexRGBA == NSColor.white.usingColorSpace(.sRGB)?.hexRGBA {
            background = .white
        } else {
            background = .custom(s.paintDefaultBackground)
        }
        return NewCanvasSpec(width: s.paintDefaultWidth, height: s.paintDefaultHeight, background: background)
    }

    struct Preset: Identifiable {
        let id: String
        let name: String
        let width: Int
        let height: Int
    }

    /// Fixed presets (the settings default and the clipboard size are added by the dialog).
    static let fixedPresets: [(name: String, width: Int, height: Int)] = [
        ("1920 × 1080", 1920, 1080),
        ("1280 × 720", 1280, 720),
        ("1024 × 768", 1024, 768),
        ("800 × 600", 800, 600),
    ]
    static let a4At150dpi = (width: 1240, height: 1754)

    var isValid: Bool { ImageResampler.isValidSize(width: width, height: height) }

    /// Each side within `AppSettings.canvasDimensionRange`, and the area within the editable pixel limit
    /// (the height is reduced when the area is too large).
    func clamped() -> NewCanvasSpec {
        var spec = self
        let range = AppSettings.canvasDimensionRange
        spec.width = min(max(width, range.lowerBound), range.upperBound)
        spec.height = min(max(height, range.lowerBound), range.upperBound)
        if spec.width * spec.height > ImageLoader.maxEditablePixels {
            spec.height = max(range.lowerBound, ImageLoader.maxEditablePixels / spec.width)
        }
        return spec
    }

    /// nil → transparent.
    func cgBackground(secondary: NSColor) -> CGColor? {
        let color: NSColor
        switch background {
        case .transparent: return nil
        case .white: color = .white
        case .secondary: color = secondary
        case .custom(let c): color = c
        }
        return color.usingColorSpace(.sRGB)?.cgColor ?? NSColor.white.cgColor
    }
}
