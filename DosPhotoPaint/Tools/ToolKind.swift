import AppKit

/// Every Paint tool. Raw values are persisted.
enum ToolKind: String, CaseIterable, Identifiable, Sendable {
    case rectangleSelect, lassoSelect, crop
    case pen, brush, eraser, fill, eyedropper, text, shape
    case hand

    var id: String { rawValue }

    /// Single-key shortcut (only active while the canvas has keyboard focus, never while typing).
    var shortcutKey: String? {
        switch self {
        case .rectangleSelect: "v"
        case .lassoSelect: "l"
        case .crop: "c"
        case .pen: "p"
        case .brush: "b"
        case .eraser: "e"
        case .fill: "g"
        case .eyedropper: "i"
        case .text: "t"
        case .shape: "u"
        case .hand: "h"
        }
    }

    var symbolName: String {
        switch self {
        case .rectangleSelect: "rectangle.dashed"
        case .lassoSelect: "lasso"
        case .crop: "crop"
        case .pen: "pencil"
        case .brush: "paintbrush.pointed"
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .eyedropper: "eyedropper"
        case .text: "textformat"
        case .shape: "square.on.circle"
        case .hand: "hand.raised"
        }
    }

    var localizedName: String {
        switch self {
        case .rectangleSelect: String(localized: "Rectangle Select", table: "Paint")
        case .lassoSelect: String(localized: "Free-Form Select", table: "Paint")
        case .crop: String(localized: "Crop", table: "Paint")
        case .pen: String(localized: "Pen", table: "Paint")
        case .brush: String(localized: "Brush", table: "Paint")
        case .eraser: String(localized: "Eraser", table: "Paint")
        case .fill: String(localized: "Fill", table: "Paint")
        case .eyedropper: String(localized: "Eyedropper", table: "Paint")
        case .text: String(localized: "Text", table: "Paint")
        case .shape: String(localized: "Shapes", table: "Paint")
        case .hand: String(localized: "Hand", table: "Paint")
        }
    }

    static func forShortcut(_ key: String) -> ToolKind? {
        allCases.first { $0.shortcutKey == key.lowercased() }
    }
}

enum BrushType: String, CaseIterable, Identifiable, Sendable {
    case round, soft, hard
    var id: String { rawValue }
}

enum EraserMode: String, CaseIterable, Identifiable, Sendable {
    /// Always erase alpha to transparent.
    case transparent
    /// On the bottom (background) layer, paint the secondary/background colour instead.
    case backgroundColorOnBackgroundLayer
    var id: String { rawValue }
}

enum ShapeKind: String, CaseIterable, Identifiable, Sendable {
    case line, rectangle, roundedRectangle, ellipse, circle, triangle, polygon, arrow, curve
    var id: String { rawValue }
}

enum TextAlignmentSetting: String, CaseIterable, Identifiable, Sendable {
    case left, center, right
    var id: String { rawValue }
    var nsAlignment: NSTextAlignment {
        switch self { case .left: .left; case .center: .center; case .right: .right }
    }
}

enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case free, original, square, fourThree, sixteenNine
    var id: String { rawValue }
    /// width / height, nil for free. `original` is resolved by the caller from the canvas size.
    var ratio: CGFloat? {
        switch self {
        case .free, .original: nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        }
    }
}
