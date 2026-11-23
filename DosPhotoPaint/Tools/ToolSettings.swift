import AppKit
import Observation

/// Current tool and tool options. App-wide (like MS Paint) and persisted when
/// "Remember tool settings" is on.
@Observable
final class ToolSettings {
    static let shared = ToolSettings()

    var tool: ToolKind { didSet { persist() } }
    /// Stroke / text colour.
    var primaryColor: NSColor { didSet { persist() } }
    /// Shape fill colour; also the "background colour" for the eraser on the background layer.
    var secondaryColor: NSColor { didSet { persist() } }
    /// 0…1, applies to pen/brush/shapes/fill.
    var opacity: Double { didSet { persist() } }

    var penWidth: Double { didSet { persist() } }
    var brushSize: Double { didSet { persist() } }
    var brushHardness: Double { didSet { persist() } }
    var brushType: BrushType { didSet { persist() } }
    var eraserSize: Double { didSet { persist() } }
    var eraserMode: EraserMode { didSet { persist() } }
    /// Use tablet pressure for width where available.
    var usePressure: Bool { didSet { persist() } }

    /// 0…255 per-channel tolerance.
    var fillTolerance: Double { didSet { persist() } }
    var fillContiguous: Bool { didSet { persist() } }

    var shapeKind: ShapeKind { didSet { persist() } }
    var shapeStrokeEnabled: Bool { didSet { persist() } }
    var shapeFillEnabled: Bool { didSet { persist() } }
    var shapeLineWidth: Double { didSet { persist() } }
    var polygonSides: Int { didSet { persist() } }
    var cornerRadius: Double { didSet { persist() } }

    var fontName: String { didSet { persist() } }
    var fontSize: Double { didSet { persist() } }
    var bold: Bool { didSet { persist() } }
    var italic: Bool { didSet { persist() } }
    var underline: Bool { didSet { persist() } }
    var textAlignment: TextAlignmentSetting { didSet { persist() } }

    /// When on, pixels equal to the secondary colour become transparent in moved/pasted selections.
    var transparentSelection: Bool { didSet { persist() } }
    var cropAspect: CropAspect { didSet { persist() } }

    static let sizeRange = 1.0...500.0
    static let fontSizeRange = 4.0...1000.0
    static let polygonSidesRange = 3...24

    @ObservationIgnored private var loading = true
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = AppRuntime.defaults, settings: AppSettings = .shared) {
        self.defaults = defaults
        tool = ToolKind(rawValue: settings.paintInitialTool) ?? .pen
        primaryColor = settings.paintInitialColor
        secondaryColor = settings.paintDefaultBackground
        opacity = 1
        penWidth = Double(settings.paintInitialLineWidth)
        brushSize = 12
        brushHardness = 0.8
        brushType = .round
        eraserSize = 16
        eraserMode = .transparent
        usePressure = true
        fillTolerance = 32
        fillContiguous = true
        shapeKind = .rectangle
        shapeStrokeEnabled = true
        shapeFillEnabled = false
        shapeLineWidth = Double(settings.paintInitialLineWidth)
        polygonSides = 5
        cornerRadius = 16
        fontName = NSFont.systemFont(ofSize: 12).fontName
        fontSize = 32
        bold = false
        italic = false
        underline = false
        textAlignment = .left
        transparentSelection = false
        cropAspect = .free
        if settings.paintRememberToolSettings { restore() }
        loading = false
    }

    // MARK: - Persistence

    private var storageKey: String { SettingsKey.toolStatePrefix + "v1" }

    private func persist() {
        guard !loading, AppSettings.shared.paintRememberToolSettings else { return }
        let dict: [String: Any] = [
            "tool": tool.rawValue, "primary": primaryColor.hexRGBA, "secondary": secondaryColor.hexRGBA,
            "opacity": opacity, "penWidth": penWidth, "brushSize": brushSize, "brushHardness": brushHardness,
            "brushType": brushType.rawValue, "eraserSize": eraserSize, "eraserMode": eraserMode.rawValue,
            "usePressure": usePressure, "fillTolerance": fillTolerance, "fillContiguous": fillContiguous,
            "shapeKind": shapeKind.rawValue, "shapeStroke": shapeStrokeEnabled, "shapeFill": shapeFillEnabled,
            "shapeLineWidth": shapeLineWidth, "polygonSides": polygonSides, "cornerRadius": cornerRadius,
            "fontName": fontName, "fontSize": fontSize, "bold": bold, "italic": italic, "underline": underline,
            "textAlignment": textAlignment.rawValue, "transparentSelection": transparentSelection,
            "cropAspect": cropAspect.rawValue,
        ]
        defaults.set(dict, forKey: storageKey)
    }

    private func restore() {
        guard let d = defaults.dictionary(forKey: storageKey) else { return }
        func dbl(_ k: String, _ range: ClosedRange<Double>) -> Double? {
            (d[k] as? NSNumber).map { min(max($0.doubleValue, range.lowerBound), range.upperBound) }.flatMap { $0.isFinite ? $0 : nil }
        }
        if let v = (d["tool"] as? String).flatMap(ToolKind.init) { tool = v }
        if let v = (d["primary"] as? String).flatMap(NSColor.init(hexRGBA:)) { primaryColor = v }
        if let v = (d["secondary"] as? String).flatMap(NSColor.init(hexRGBA:)) { secondaryColor = v }
        if let v = dbl("opacity", 0...1) { opacity = v }
        if let v = dbl("penWidth", Self.sizeRange) { penWidth = v }
        if let v = dbl("brushSize", Self.sizeRange) { brushSize = v }
        if let v = dbl("brushHardness", 0...1) { brushHardness = v }
        if let v = (d["brushType"] as? String).flatMap(BrushType.init) { brushType = v }
        if let v = dbl("eraserSize", Self.sizeRange) { eraserSize = v }
        if let v = (d["eraserMode"] as? String).flatMap(EraserMode.init) { eraserMode = v }
        if let v = d["usePressure"] as? Bool { usePressure = v }
        if let v = dbl("fillTolerance", 0...255) { fillTolerance = v }
        if let v = d["fillContiguous"] as? Bool { fillContiguous = v }
        if let v = (d["shapeKind"] as? String).flatMap(ShapeKind.init) { shapeKind = v }
        if let v = d["shapeStroke"] as? Bool { shapeStrokeEnabled = v }
        if let v = d["shapeFill"] as? Bool { shapeFillEnabled = v }
        if let v = dbl("shapeLineWidth", Self.sizeRange) { shapeLineWidth = v }
        if let v = (d["polygonSides"] as? NSNumber)?.intValue { polygonSides = min(max(v, Self.polygonSidesRange.lowerBound), Self.polygonSidesRange.upperBound) }
        if let v = dbl("cornerRadius", 0...1000) { cornerRadius = v }
        if let v = d["fontName"] as? String, NSFont(name: v, size: 12) != nil { fontName = v }
        if let v = dbl("fontSize", Self.fontSizeRange) { fontSize = v }
        if let v = d["bold"] as? Bool { bold = v }
        if let v = d["italic"] as? Bool { italic = v }
        if let v = d["underline"] as? Bool { underline = v }
        if let v = (d["textAlignment"] as? String).flatMap(TextAlignmentSetting.init) { textAlignment = v }
        if let v = d["transparentSelection"] as? Bool { transparentSelection = v }
        if let v = (d["cropAspect"] as? String).flatMap(CropAspect.init) { cropAspect = v }
    }

    /// Swaps primary and secondary colours (X key).
    func swapColors() {
        let p = primaryColor
        primaryColor = secondaryColor
        secondaryColor = p
    }
}
