import Foundation

/// Localized picker labels for every settings enum (Settings string table).
private func s(_ key: String.LocalizationValue) -> String { String(localized: key, table: "Settings") }

extension AppLanguageSetting {
    /// Language names are shown in their own language so they stay recognisable after a wrong switch.
    var settingsLabel: String {
        switch self {
        case .system: s("System Default")
        case .japanese: "日本語"
        case .english: "English"
        }
    }
}

extension AppearanceSetting {
    var settingsLabel: String {
        switch self {
        case .system: s("System")
        case .light: s("Light")
        case .dark: s("Dark")
        }
    }
}

extension StartupMode {
    var settingsLabel: String {
        switch self {
        case .automatic: s("Automatic (photo if a file is opened, otherwise canvas)")
        case .photo: s("Photo (show the Open panel)")
        case .paint: s("Paint (new canvas)")
        }
    }
}

extension InitialZoomSetting {
    var settingsLabel: String {
        switch self {
        case .fitWindow: s("Fit to Window")
        case .actualSize: s("Actual Size")
        case .fitWidth: s("Fit Width")
        case .fitHeight: s("Fit Height")
        }
    }
}

extension InterpolationSetting {
    var settingsLabel: String {
        switch self {
        case .automatic: s("Automatic")
        case .smooth: s("Smooth")
        case .nearestNeighbor: s("Pixelated (Nearest Neighbor)")
        }
    }
}

extension ViewerBackgroundSetting {
    var settingsLabel: String {
        switch self {
        case .darkGray: s("Dark Gray")
        case .black: s("Black")
        case .lightGray: s("Light Gray")
        case .white: s("White")
        case .window: s("Window Background")
        }
    }
}

extension ToolPalettePosition {
    var settingsLabel: String {
        switch self {
        case .top: s("Top (horizontal)")
        case .left: s("Left (vertical)")
        }
    }
}

extension WheelBehavior {
    var settingsLabel: String {
        switch self {
        case .scroll: s("Scroll")
        case .zoom: s("Zoom")
        case .navigate: s("Previous / Next Image")
        }
    }
}

extension ImageSortOrder {
    var settingsLabel: String {
        switch self {
        case .naturalName: s("Name (Natural)")
        case .name: s("Name")
        case .modificationDate: s("Date Modified")
        case .creationDate: s("Date Created")
        }
    }
}

extension ZoomOnNavigateSetting {
    var settingsLabel: String {
        switch self {
        case .automatic: s("Apply initial zoom to each image")
        case .keep: s("Keep current zoom")
        }
    }
}

extension DoubleClickAction {
    var settingsLabel: String {
        switch self {
        case .toggleFitActual: s("Toggle Fit / Actual Size")
        case .toggleFullScreen: s("Toggle Full Screen")
        case .none: s("Do Nothing")
        }
    }
}

extension PixelGridSetting {
    var settingsLabel: String {
        switch self {
        case .off: s("Never")
        case .highZoom: s("At High Zoom")
        }
    }
}

extension ColorProfilePolicy {
    var settingsLabel: String {
        switch self {
        case .preserve: s("Preserve Original Profile")
        case .convertToSRGB: s("Convert to sRGB")
        }
    }
}

extension OverwriteConfirmation {
    var settingsLabel: String {
        switch self {
        case .whenNeeded: s("Only When Information Would Be Lost")
        case .always: s("Always")
        }
    }
}

extension ImageFileFormat {
    var settingsLabel: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .bmp: "BMP"
        }
    }
}

extension SlideshowFit {
    var settingsLabel: String {
        switch self {
        case .fit: s("Fit to Screen")
        case .actualSize: s("Actual Size")
        }
    }
}

extension SlideshowTransition {
    var settingsLabel: String {
        switch self {
        case .none: s("None")
        case .dissolve: s("Dissolve")
        }
    }
}

extension PerformancePreset {
    var settingsLabel: String {
        switch self {
        case .automatic: s("Automatic")
        case .lowMemory: s("Low Memory")
        case .highQuality: s("High Quality")
        }
    }
}
