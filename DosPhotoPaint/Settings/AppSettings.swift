import AppKit
import Observation

// MARK: - Setting value types

enum AppLanguageSetting: String, CaseIterable, Identifiable, Sendable {
    case system, japanese = "ja", english = "en"
    var id: String { rawValue }
}

enum AppearanceSetting: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// `automatic`: a file given → Photo, nothing given → Paint.
enum StartupMode: String, CaseIterable, Identifiable, Sendable {
    case automatic, photo, paint
    var id: String { rawValue }
}

enum InitialZoomSetting: String, CaseIterable, Identifiable, Sendable {
    case fitWindow, actualSize, fitWidth, fitHeight
    var id: String { rawValue }
}

enum InterpolationSetting: String, CaseIterable, Identifiable, Sendable {
    /// Smooth when shrinking / moderate zoom, nearest neighbour at high zoom.
    case automatic, smooth, nearestNeighbor
    var id: String { rawValue }
}

enum ViewerBackgroundSetting: String, CaseIterable, Identifiable, Sendable {
    case darkGray, black, lightGray, white, window
    var id: String { rawValue }
    var color: NSColor {
        switch self {
        case .darkGray: NSColor(white: 0.16, alpha: 1)
        case .black: .black
        case .lightGray: NSColor(white: 0.82, alpha: 1)
        case .white: .white
        case .window: .windowBackgroundColor
        }
    }
}

/// Layout of the Photo Mode image browser.
enum ImageBrowserStyle: String, CaseIterable, Identifiable, Sendable {
    case tiles, list
    var id: String { rawValue }
}

enum WheelBehavior: String, CaseIterable, Identifiable, Sendable {
    case scroll, zoom, navigate
    var id: String { rawValue }
}

enum ImageSortOrder: String, CaseIterable, Identifiable, Sendable {
    case naturalName, name, modificationDate, creationDate
    var id: String { rawValue }
}

enum ZoomOnNavigateSetting: String, CaseIterable, Identifiable, Sendable {
    /// Re-apply the initial zoom rule for each image.
    case automatic
    /// Keep the current magnification.
    case keep
    var id: String { rawValue }
}

enum DoubleClickAction: String, CaseIterable, Identifiable, Sendable {
    case toggleFitActual, toggleFullScreen, none
    var id: String { rawValue }
}

/// Where the Paint tool palette is shown. `top` is a horizontal ribbon above the canvas (like
/// Windows Paint); `left` is the vertical palette in a side pane.
enum ToolPalettePosition: String, CaseIterable, Identifiable, Sendable {
    case top, left
    var id: String { rawValue }
}

enum PixelGridSetting: String, CaseIterable, Identifiable, Sendable {
    case off, highZoom
    var id: String { rawValue }
}

enum ColorProfilePolicy: String, CaseIterable, Identifiable, Sendable {
    case preserve, convertToSRGB
    var id: String { rawValue }
}

enum OverwriteConfirmation: String, CaseIterable, Identifiable, Sendable {
    /// Confirm when the save would lose information (flattening layers, lossy format).
    case whenNeeded, always
    var id: String { rawValue }
}

enum ImageFileFormat: String, CaseIterable, Identifiable, Sendable {
    case png, jpeg, heic, tiff, bmp
    var id: String { rawValue }
}

enum SlideshowFit: String, CaseIterable, Identifiable, Sendable {
    case fit, actualSize
    var id: String { rawValue }
}

enum SlideshowTransition: String, CaseIterable, Identifiable, Sendable {
    case none, dissolve
    var id: String { rawValue }
}

enum PerformancePreset: String, CaseIterable, Identifiable, Sendable {
    case automatic, lowMemory, highQuality
    var id: String { rawValue }
}

// MARK: - Keys

/// All UserDefaults keys used by the app. Keep in one place.
nonisolated enum SettingsKey {
    static let language = "general.language"
    static let appearance = "general.appearance"
    static let startupMode = "general.startupMode"
    static let recentDocumentsLimit = "general.recentDocumentsLimit"
    static let restoreWindows = "general.restoreWindows"
    static let confirmUnsavedOnClose = "general.confirmUnsavedOnClose"
    static let showStatusBar = "general.showStatusBar"
    static let showToolbar = "general.showToolbar"

    static let photoInitialZoom = "photo.initialZoom"
    static let photoInterpolation = "photo.interpolation"
    static let photoBackground = "photo.background"
    static let photoCheckerboard = "photo.checkerboard"
    static let photoWheel = "photo.wheel"
    static let photoCommandWheel = "photo.commandWheel"
    static let photoZoomAtCursor = "photo.zoomAtCursor"
    static let photoFolderNavigation = "photo.folderNavigation"
    static let photoSortOrder = "photo.sortOrder"
    static let photoLoopNavigation = "photo.loopNavigation"
    static let photoPreloadCount = "photo.preloadCount"
    static let photoAutoplayGIF = "photo.autoplayGIF"
    static let photoZoomOnNavigate = "photo.zoomOnNavigate"
    static let photoDoubleClick = "photo.doubleClick"
    static let photoBrowserStyle = "photo.browserStyle"
    static let photoBrowserIncludeSubfolders = "photo.browserIncludeSubfolders"
    static let photoBrowserThumbnailSize = "photo.browserThumbnailSize"

    static let paintDefaultWidth = "paint.defaultWidth"
    static let paintDefaultHeight = "paint.defaultHeight"
    static let paintDefaultBackground = "paint.defaultBackground"
    static let paintTransparentBackground = "paint.transparentBackground"
    static let paintInitialTool = "paint.initialTool"
    static let paintInitialLineWidth = "paint.initialLineWidth"
    static let paintInitialColor = "paint.initialColor"
    static let paintAntialiasing = "paint.antialiasing"
    static let paintShowGrid = "paint.showGrid"
    static let paintGridSpacing = "paint.gridSpacing"
    static let paintPixelGrid = "paint.pixelGrid"
    static let paintShowSelectionOutline = "paint.showSelectionOutline"
    static let paintRememberToolSettings = "paint.rememberToolSettings"
    static let paintUndoLevels = "paint.undoLevels"
    static let paintToolPalettePosition = "paint.toolPalettePosition"

    static let saveDefaultFormat = "save.defaultFormat"
    static let saveJPEGQuality = "save.jpegQuality"
    static let saveColorProfile = "save.colorProfile"
    static let saveStripGPS = "save.stripGPS"
    static let saveKeepMetadata = "save.keepMetadata"
    static let saveOverwriteConfirmation = "save.overwriteConfirmation"
    static let saveAutoRecover = "save.autoRecover"
    static let saveJPEGBackground = "save.jpegBackground"

    static let slideshowInterval = "slideshow.interval"
    static let slideshowLoop = "slideshow.loop"
    static let slideshowShuffle = "slideshow.shuffle"
    static let slideshowFullScreen = "slideshow.fullScreen"
    static let slideshowFit = "slideshow.fit"
    static let slideshowTransition = "slideshow.transition"

    static let performancePreset = "performance.preset"
    static let performanceCacheMB = "performance.cacheMB"
    static let performancePreloadEnabled = "performance.preloadEnabled"
    static let performanceHighQualityInterpolation = "performance.highQualityInterpolation"
    static let performanceReleaseOnMemoryPressure = "performance.releaseOnMemoryPressure"

    static let toolStatePrefix = "toolState."
}

// MARK: - Store

/// Single source of truth for user preferences.
///
/// Values are written through to `UserDefaults` immediately, validated on read
/// (unknown enum raw values / out-of-range numbers fall back to the default or
/// are clamped), and observable via the Observation framework.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    // Ranges (also used by the settings UI)
    nonisolated static let recentDocumentsRange = 0...50
    static let preloadRange = 0...5
    static let canvasDimensionRange = 1...16_384
    static let lineWidthRange = 1...500
    static let gridSpacingRange = 2...512
    static let undoLevelsRange = 5...200
    static let jpegQualityRange = 0.1...1.0
    static let slideshowIntervalRange = 1.0...60.0
    static let cacheMBRange = 64...4096
    /// Tile thumbnail edge in points (list rows use a quarter of it).
    static let browserThumbnailRange = 64...320

    init(defaults: UserDefaults = AppRuntime.defaults) {
        self.defaults = defaults
        language = Self.enumValue(defaults, SettingsKey.language, .system)
        appearance = Self.enumValue(defaults, SettingsKey.appearance, .system)
        startupMode = Self.enumValue(defaults, SettingsKey.startupMode, .automatic)
        recentDocumentsLimit = Self.intValue(defaults, SettingsKey.recentDocumentsLimit, 20, Self.recentDocumentsRange)
        restoreWindows = Self.boolValue(defaults, SettingsKey.restoreWindows, true)
        confirmUnsavedOnClose = Self.boolValue(defaults, SettingsKey.confirmUnsavedOnClose, true)
        showStatusBar = Self.boolValue(defaults, SettingsKey.showStatusBar, true)
        showToolbar = Self.boolValue(defaults, SettingsKey.showToolbar, true)

        photoInitialZoom = Self.enumValue(defaults, SettingsKey.photoInitialZoom, .fitWindow)
        photoInterpolation = Self.enumValue(defaults, SettingsKey.photoInterpolation, .automatic)
        photoBackground = Self.enumValue(defaults, SettingsKey.photoBackground, .darkGray)
        photoCheckerboard = Self.boolValue(defaults, SettingsKey.photoCheckerboard, true)
        photoWheel = Self.enumValue(defaults, SettingsKey.photoWheel, .scroll)
        photoCommandWheel = Self.enumValue(defaults, SettingsKey.photoCommandWheel, .zoom)
        photoZoomAtCursor = Self.boolValue(defaults, SettingsKey.photoZoomAtCursor, true)
        photoFolderNavigation = Self.boolValue(defaults, SettingsKey.photoFolderNavigation, true)
        photoSortOrder = Self.enumValue(defaults, SettingsKey.photoSortOrder, .naturalName)
        photoLoopNavigation = Self.boolValue(defaults, SettingsKey.photoLoopNavigation, false)
        photoPreloadCount = Self.intValue(defaults, SettingsKey.photoPreloadCount, 2, Self.preloadRange)
        photoAutoplayGIF = Self.boolValue(defaults, SettingsKey.photoAutoplayGIF, true)
        photoZoomOnNavigate = Self.enumValue(defaults, SettingsKey.photoZoomOnNavigate, .automatic)
        photoDoubleClick = Self.enumValue(defaults, SettingsKey.photoDoubleClick, .toggleFitActual)
        photoBrowserStyle = Self.enumValue(defaults, SettingsKey.photoBrowserStyle, .tiles)
        photoBrowserIncludeSubfolders = Self.boolValue(defaults, SettingsKey.photoBrowserIncludeSubfolders, false)
        photoBrowserThumbnailSize = Self.intValue(defaults, SettingsKey.photoBrowserThumbnailSize, 140, Self.browserThumbnailRange)

        paintDefaultWidth = Self.intValue(defaults, SettingsKey.paintDefaultWidth, 1920, Self.canvasDimensionRange)
        paintDefaultHeight = Self.intValue(defaults, SettingsKey.paintDefaultHeight, 1080, Self.canvasDimensionRange)
        paintDefaultBackground = Self.colorValue(defaults, SettingsKey.paintDefaultBackground, .white)
        paintTransparentBackground = Self.boolValue(defaults, SettingsKey.paintTransparentBackground, false)
        paintInitialTool = Self.stringValue(defaults, SettingsKey.paintInitialTool, "pen")
        paintInitialLineWidth = Self.intValue(defaults, SettingsKey.paintInitialLineWidth, 3, Self.lineWidthRange)
        paintInitialColor = Self.colorValue(defaults, SettingsKey.paintInitialColor, .black)
        paintAntialiasing = Self.boolValue(defaults, SettingsKey.paintAntialiasing, true)
        paintShowGrid = Self.boolValue(defaults, SettingsKey.paintShowGrid, false)
        paintGridSpacing = Self.intValue(defaults, SettingsKey.paintGridSpacing, 16, Self.gridSpacingRange)
        paintPixelGrid = Self.enumValue(defaults, SettingsKey.paintPixelGrid, .highZoom)
        paintShowSelectionOutline = Self.boolValue(defaults, SettingsKey.paintShowSelectionOutline, true)
        paintRememberToolSettings = Self.boolValue(defaults, SettingsKey.paintRememberToolSettings, true)
        paintUndoLevels = Self.intValue(defaults, SettingsKey.paintUndoLevels, 50, Self.undoLevelsRange)
        paintToolPalettePosition = Self.enumValue(defaults, SettingsKey.paintToolPalettePosition, .top)

        saveDefaultFormat = Self.enumValue(defaults, SettingsKey.saveDefaultFormat, .png)
        saveJPEGQuality = Self.doubleValue(defaults, SettingsKey.saveJPEGQuality, 0.9, Self.jpegQualityRange)
        saveColorProfile = Self.enumValue(defaults, SettingsKey.saveColorProfile, .preserve)
        saveStripGPS = Self.boolValue(defaults, SettingsKey.saveStripGPS, true)
        saveKeepMetadata = Self.boolValue(defaults, SettingsKey.saveKeepMetadata, true)
        saveOverwriteConfirmation = Self.enumValue(defaults, SettingsKey.saveOverwriteConfirmation, .whenNeeded)
        saveAutoRecover = Self.boolValue(defaults, SettingsKey.saveAutoRecover, true)
        saveJPEGBackground = Self.colorValue(defaults, SettingsKey.saveJPEGBackground, .white)

        slideshowInterval = Self.doubleValue(defaults, SettingsKey.slideshowInterval, 5, Self.slideshowIntervalRange)
        slideshowLoop = Self.boolValue(defaults, SettingsKey.slideshowLoop, true)
        slideshowShuffle = Self.boolValue(defaults, SettingsKey.slideshowShuffle, false)
        slideshowFullScreen = Self.boolValue(defaults, SettingsKey.slideshowFullScreen, true)
        slideshowFit = Self.enumValue(defaults, SettingsKey.slideshowFit, .fit)
        slideshowTransition = Self.enumValue(defaults, SettingsKey.slideshowTransition, .none)

        performancePreset = Self.enumValue(defaults, SettingsKey.performancePreset, .automatic)
        performanceCacheMB = Self.intValue(defaults, SettingsKey.performanceCacheMB, 512, Self.cacheMBRange)
        performancePreloadEnabled = Self.boolValue(defaults, SettingsKey.performancePreloadEnabled, true)
        performanceHighQualityInterpolation = Self.boolValue(defaults, SettingsKey.performanceHighQualityInterpolation, true)
        performanceReleaseOnMemoryPressure = Self.boolValue(defaults, SettingsKey.performanceReleaseOnMemoryPressure, true)
    }

    // MARK: General
    var language: AppLanguageSetting { didSet { set(language.rawValue, SettingsKey.language) } }
    var appearance: AppearanceSetting { didSet { set(appearance.rawValue, SettingsKey.appearance); NSApp?.appearance = appearance.nsAppearance } }
    var startupMode: StartupMode { didSet { set(startupMode.rawValue, SettingsKey.startupMode) } }
    var recentDocumentsLimit: Int { didSet { clampAndSet(\.recentDocumentsLimit, Self.recentDocumentsRange, SettingsKey.recentDocumentsLimit) } }
    var restoreWindows: Bool { didSet { set(restoreWindows, SettingsKey.restoreWindows); applyWindowRestoration() } }
    var confirmUnsavedOnClose: Bool { didSet { set(confirmUnsavedOnClose, SettingsKey.confirmUnsavedOnClose) } }
    var showStatusBar: Bool { didSet { set(showStatusBar, SettingsKey.showStatusBar) } }
    var showToolbar: Bool { didSet { set(showToolbar, SettingsKey.showToolbar) } }

    // MARK: Photo
    var photoInitialZoom: InitialZoomSetting { didSet { set(photoInitialZoom.rawValue, SettingsKey.photoInitialZoom) } }
    var photoInterpolation: InterpolationSetting { didSet { set(photoInterpolation.rawValue, SettingsKey.photoInterpolation) } }
    var photoBackground: ViewerBackgroundSetting { didSet { set(photoBackground.rawValue, SettingsKey.photoBackground) } }
    var photoCheckerboard: Bool { didSet { set(photoCheckerboard, SettingsKey.photoCheckerboard) } }
    var photoWheel: WheelBehavior { didSet { set(photoWheel.rawValue, SettingsKey.photoWheel) } }
    var photoCommandWheel: WheelBehavior { didSet { set(photoCommandWheel.rawValue, SettingsKey.photoCommandWheel) } }
    var photoZoomAtCursor: Bool { didSet { set(photoZoomAtCursor, SettingsKey.photoZoomAtCursor) } }
    var photoFolderNavigation: Bool { didSet { set(photoFolderNavigation, SettingsKey.photoFolderNavigation) } }
    var photoSortOrder: ImageSortOrder { didSet { set(photoSortOrder.rawValue, SettingsKey.photoSortOrder) } }
    var photoLoopNavigation: Bool { didSet { set(photoLoopNavigation, SettingsKey.photoLoopNavigation) } }
    var photoPreloadCount: Int { didSet { clampAndSet(\.photoPreloadCount, Self.preloadRange, SettingsKey.photoPreloadCount) } }
    var photoAutoplayGIF: Bool { didSet { set(photoAutoplayGIF, SettingsKey.photoAutoplayGIF) } }
    var photoZoomOnNavigate: ZoomOnNavigateSetting { didSet { set(photoZoomOnNavigate.rawValue, SettingsKey.photoZoomOnNavigate) } }
    var photoDoubleClick: DoubleClickAction { didSet { set(photoDoubleClick.rawValue, SettingsKey.photoDoubleClick) } }
    var photoBrowserStyle: ImageBrowserStyle { didSet { set(photoBrowserStyle.rawValue, SettingsKey.photoBrowserStyle) } }
    var photoBrowserIncludeSubfolders: Bool { didSet { set(photoBrowserIncludeSubfolders, SettingsKey.photoBrowserIncludeSubfolders) } }
    var photoBrowserThumbnailSize: Int { didSet { clampAndSet(\.photoBrowserThumbnailSize, Self.browserThumbnailRange, SettingsKey.photoBrowserThumbnailSize) } }

    // MARK: Paint
    var paintDefaultWidth: Int { didSet { clampAndSet(\.paintDefaultWidth, Self.canvasDimensionRange, SettingsKey.paintDefaultWidth) } }
    var paintDefaultHeight: Int { didSet { clampAndSet(\.paintDefaultHeight, Self.canvasDimensionRange, SettingsKey.paintDefaultHeight) } }
    var paintDefaultBackground: NSColor { didSet { set(paintDefaultBackground.hexRGBA, SettingsKey.paintDefaultBackground) } }
    var paintTransparentBackground: Bool { didSet { set(paintTransparentBackground, SettingsKey.paintTransparentBackground) } }
    /// Raw value of `ToolKind`; validated by the tools layer.
    var paintInitialTool: String { didSet { set(paintInitialTool, SettingsKey.paintInitialTool) } }
    var paintInitialLineWidth: Int { didSet { clampAndSet(\.paintInitialLineWidth, Self.lineWidthRange, SettingsKey.paintInitialLineWidth) } }
    var paintInitialColor: NSColor { didSet { set(paintInitialColor.hexRGBA, SettingsKey.paintInitialColor) } }
    var paintAntialiasing: Bool { didSet { set(paintAntialiasing, SettingsKey.paintAntialiasing) } }
    var paintShowGrid: Bool { didSet { set(paintShowGrid, SettingsKey.paintShowGrid) } }
    var paintGridSpacing: Int { didSet { clampAndSet(\.paintGridSpacing, Self.gridSpacingRange, SettingsKey.paintGridSpacing) } }
    var paintPixelGrid: PixelGridSetting { didSet { set(paintPixelGrid.rawValue, SettingsKey.paintPixelGrid) } }
    var paintShowSelectionOutline: Bool { didSet { set(paintShowSelectionOutline, SettingsKey.paintShowSelectionOutline) } }
    var paintRememberToolSettings: Bool { didSet { set(paintRememberToolSettings, SettingsKey.paintRememberToolSettings) } }
    var paintUndoLevels: Int { didSet { clampAndSet(\.paintUndoLevels, Self.undoLevelsRange, SettingsKey.paintUndoLevels) } }
    var paintToolPalettePosition: ToolPalettePosition { didSet { set(paintToolPalettePosition.rawValue, SettingsKey.paintToolPalettePosition) } }

    // MARK: Save
    var saveDefaultFormat: ImageFileFormat { didSet { set(saveDefaultFormat.rawValue, SettingsKey.saveDefaultFormat) } }
    var saveJPEGQuality: Double { didSet { clampAndSet(\.saveJPEGQuality, Self.jpegQualityRange, SettingsKey.saveJPEGQuality) } }
    var saveColorProfile: ColorProfilePolicy { didSet { set(saveColorProfile.rawValue, SettingsKey.saveColorProfile) } }
    var saveStripGPS: Bool { didSet { set(saveStripGPS, SettingsKey.saveStripGPS) } }
    var saveKeepMetadata: Bool { didSet { set(saveKeepMetadata, SettingsKey.saveKeepMetadata) } }
    var saveOverwriteConfirmation: OverwriteConfirmation { didSet { set(saveOverwriteConfirmation.rawValue, SettingsKey.saveOverwriteConfirmation) } }
    var saveAutoRecover: Bool { didSet { set(saveAutoRecover, SettingsKey.saveAutoRecover); applyAutosave() } }
    var saveJPEGBackground: NSColor { didSet { set(saveJPEGBackground.hexRGBA, SettingsKey.saveJPEGBackground) } }

    // MARK: Slideshow
    var slideshowInterval: Double { didSet { clampAndSet(\.slideshowInterval, Self.slideshowIntervalRange, SettingsKey.slideshowInterval) } }
    var slideshowLoop: Bool { didSet { set(slideshowLoop, SettingsKey.slideshowLoop) } }
    var slideshowShuffle: Bool { didSet { set(slideshowShuffle, SettingsKey.slideshowShuffle) } }
    var slideshowFullScreen: Bool { didSet { set(slideshowFullScreen, SettingsKey.slideshowFullScreen) } }
    var slideshowFit: SlideshowFit { didSet { set(slideshowFit.rawValue, SettingsKey.slideshowFit) } }
    var slideshowTransition: SlideshowTransition { didSet { set(slideshowTransition.rawValue, SettingsKey.slideshowTransition) } }

    // MARK: Performance
    var performancePreset: PerformancePreset { didSet { set(performancePreset.rawValue, SettingsKey.performancePreset); applyPreset() } }
    var performanceCacheMB: Int { didSet { clampAndSet(\.performanceCacheMB, Self.cacheMBRange, SettingsKey.performanceCacheMB) } }
    var performancePreloadEnabled: Bool { didSet { set(performancePreloadEnabled, SettingsKey.performancePreloadEnabled) } }
    var performanceHighQualityInterpolation: Bool { didSet { set(performanceHighQualityInterpolation, SettingsKey.performanceHighQualityInterpolation) } }
    var performanceReleaseOnMemoryPressure: Bool { didSet { set(performanceReleaseOnMemoryPressure, SettingsKey.performanceReleaseOnMemoryPressure) } }

    /// Effective preload count (0 when preloading is disabled).
    var effectivePreloadCount: Int { performancePreloadEnabled ? photoPreloadCount : 0 }

    /// Effective cache budget in bytes.
    var effectiveCacheBytes: Int { performanceCacheMB * 1024 * 1024 }

    // MARK: - Side effects

    /// Applies settings that map onto AppKit-level behaviour. Called at launch and on change.
    func applySystemIntegration() {
        NSApp?.appearance = appearance.nsAppearance
        applyWindowRestoration()
        applyAutosave()
    }

    private func applyWindowRestoration() {
        // AppKit honours this per-app key for "Close windows when quitting an app".
        defaults.set(restoreWindows, forKey: "NSQuitAlwaysKeepsWindows")
    }

    private func applyAutosave() {
        NSDocumentController.shared.autosavingDelay = saveAutoRecover ? 15 : 0
    }

    private func applyPreset() {
        switch performancePreset {
        case .automatic:
            performanceCacheMB = 512; performancePreloadEnabled = true; photoPreloadCount = 2
            performanceHighQualityInterpolation = true; performanceReleaseOnMemoryPressure = true
        case .lowMemory:
            performanceCacheMB = 128; performancePreloadEnabled = true; photoPreloadCount = 1
            performanceHighQualityInterpolation = false; performanceReleaseOnMemoryPressure = true
        case .highQuality:
            performanceCacheMB = 1536; performancePreloadEnabled = true; photoPreloadCount = 3
            performanceHighQualityInterpolation = true; performanceReleaseOnMemoryPressure = true
        }
    }

    /// Restores every setting to its default value.
    func resetToDefaults() {
        let fresh = AppSettings(defaults: UserDefaults(suiteName: "DosPhotoPaint.defaults.\(UUID().uuidString)")!)
        language = fresh.language; appearance = fresh.appearance; startupMode = fresh.startupMode
        recentDocumentsLimit = fresh.recentDocumentsLimit; restoreWindows = fresh.restoreWindows
        confirmUnsavedOnClose = fresh.confirmUnsavedOnClose; showStatusBar = fresh.showStatusBar; showToolbar = fresh.showToolbar
        photoInitialZoom = fresh.photoInitialZoom; photoInterpolation = fresh.photoInterpolation
        photoBackground = fresh.photoBackground; photoCheckerboard = fresh.photoCheckerboard
        photoWheel = fresh.photoWheel; photoCommandWheel = fresh.photoCommandWheel; photoZoomAtCursor = fresh.photoZoomAtCursor
        photoFolderNavigation = fresh.photoFolderNavigation; photoSortOrder = fresh.photoSortOrder
        photoLoopNavigation = fresh.photoLoopNavigation; photoPreloadCount = fresh.photoPreloadCount
        photoAutoplayGIF = fresh.photoAutoplayGIF; photoZoomOnNavigate = fresh.photoZoomOnNavigate; photoDoubleClick = fresh.photoDoubleClick
        photoBrowserStyle = fresh.photoBrowserStyle; photoBrowserIncludeSubfolders = fresh.photoBrowserIncludeSubfolders
        photoBrowserThumbnailSize = fresh.photoBrowserThumbnailSize
        paintDefaultWidth = fresh.paintDefaultWidth; paintDefaultHeight = fresh.paintDefaultHeight
        paintDefaultBackground = fresh.paintDefaultBackground; paintTransparentBackground = fresh.paintTransparentBackground
        paintInitialTool = fresh.paintInitialTool; paintInitialLineWidth = fresh.paintInitialLineWidth
        paintInitialColor = fresh.paintInitialColor; paintAntialiasing = fresh.paintAntialiasing
        paintShowGrid = fresh.paintShowGrid; paintGridSpacing = fresh.paintGridSpacing; paintPixelGrid = fresh.paintPixelGrid
        paintShowSelectionOutline = fresh.paintShowSelectionOutline; paintRememberToolSettings = fresh.paintRememberToolSettings
        paintUndoLevels = fresh.paintUndoLevels; paintToolPalettePosition = fresh.paintToolPalettePosition
        saveDefaultFormat = fresh.saveDefaultFormat; saveJPEGQuality = fresh.saveJPEGQuality
        saveColorProfile = fresh.saveColorProfile; saveStripGPS = fresh.saveStripGPS; saveKeepMetadata = fresh.saveKeepMetadata
        saveOverwriteConfirmation = fresh.saveOverwriteConfirmation; saveAutoRecover = fresh.saveAutoRecover
        saveJPEGBackground = fresh.saveJPEGBackground
        slideshowInterval = fresh.slideshowInterval; slideshowLoop = fresh.slideshowLoop; slideshowShuffle = fresh.slideshowShuffle
        slideshowFullScreen = fresh.slideshowFullScreen; slideshowFit = fresh.slideshowFit; slideshowTransition = fresh.slideshowTransition
        performancePreset = fresh.performancePreset // also re-applies preset values
        performanceCacheMB = fresh.performanceCacheMB
        performancePreloadEnabled = fresh.performancePreloadEnabled
        performanceHighQualityInterpolation = fresh.performanceHighQualityInterpolation
        performanceReleaseOnMemoryPressure = fresh.performanceReleaseOnMemoryPressure
    }

    // MARK: - Persistence helpers

    private func set(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private func clampAndSet<T: Comparable>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>, _ range: ClosedRange<T>, _ key: String) {
        let value = self[keyPath: keyPath]
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        if clamped != value { self[keyPath: keyPath] = clamped }
        defaults.set(clamped, forKey: key)
    }

    private static func enumValue<E: RawRepresentable>(_ d: UserDefaults, _ key: String, _ fallback: E) -> E where E.RawValue == String {
        guard let raw = d.string(forKey: key), let value = E(rawValue: raw) else { return fallback }
        return value
    }

    private static func boolValue(_ d: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        (d.object(forKey: key) as? Bool) ?? fallback
    }

    private static func stringValue(_ d: UserDefaults, _ key: String, _ fallback: String) -> String {
        d.string(forKey: key) ?? fallback
    }

    private static func intValue(_ d: UserDefaults, _ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
        guard let n = d.object(forKey: key) as? NSNumber else { return fallback }
        return min(max(n.intValue, range.lowerBound), range.upperBound)
    }

    private static func doubleValue(_ d: UserDefaults, _ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard let n = d.object(forKey: key) as? NSNumber, n.doubleValue.isFinite else { return fallback }
        return min(max(n.doubleValue, range.lowerBound), range.upperBound)
    }

    private static func colorValue(_ d: UserDefaults, _ key: String, _ fallback: NSColor) -> NSColor {
        guard let hex = d.string(forKey: key), let color = NSColor(hexRGBA: hex) else { return fallback }
        return color
    }
}
