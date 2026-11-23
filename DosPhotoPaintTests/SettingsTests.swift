import XCTest
import AppKit
@testable import DosPhotoPaint

nonisolated final class SettingsTests: XCTestCase {
    nonisolated private func makeDefaults() -> UserDefaults {
        let name = "DosPhotoPaint.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @MainActor func testDefaults() {
        let s = AppSettings(defaults: makeDefaults())
        XCTAssertEqual(s.startupMode, .automatic)
        XCTAssertEqual(s.paintUndoLevels, 50)
        XCTAssertEqual(s.performanceCacheMB, 512)
    }

    @MainActor func testStoredValuesAreClampedAndInvalidFallBack() {
        let d = makeDefaults()
        d.set(9999, forKey: SettingsKey.paintUndoLevels)
        d.set(-5, forKey: SettingsKey.photoPreloadCount)
        d.set("bogus", forKey: SettingsKey.appearance)
        d.set("not-a-color", forKey: SettingsKey.paintInitialColor)
        d.set("text", forKey: SettingsKey.slideshowInterval)
        d.set(Double.nan, forKey: SettingsKey.saveJPEGQuality)
        let s = AppSettings(defaults: d)
        XCTAssertEqual(s.paintUndoLevels, AppSettings.undoLevelsRange.upperBound)
        XCTAssertEqual(s.photoPreloadCount, AppSettings.preloadRange.lowerBound)
        XCTAssertEqual(s.appearance, .system)
        XCTAssertEqual(s.paintInitialColor.hexRGBA, NSColor.black.hexRGBA)
        XCTAssertEqual(s.slideshowInterval, 5)
        XCTAssertEqual(s.saveJPEGQuality, 0.9)
    }

    @MainActor func testAssignmentClamps() {
        let s = AppSettings(defaults: makeDefaults())
        s.paintDefaultWidth = 100_000
        XCTAssertEqual(s.paintDefaultWidth, AppSettings.canvasDimensionRange.upperBound)
        s.performanceCacheMB = 1
        XCTAssertEqual(s.performanceCacheMB, AppSettings.cacheMBRange.lowerBound)
        s.slideshowInterval = 0
        XCTAssertEqual(s.slideshowInterval, AppSettings.slideshowIntervalRange.lowerBound)
    }

    @MainActor func testPresetApplication() {
        let s = AppSettings(defaults: makeDefaults())
        s.performancePreset = .lowMemory
        XCTAssertEqual(s.performanceCacheMB, 128)
        XCTAssertFalse(s.performanceHighQualityInterpolation)
        XCTAssertEqual(s.photoPreloadCount, 1)
        s.performancePreset = .highQuality
        XCTAssertEqual(s.performanceCacheMB, 1536)
        XCTAssertTrue(s.performanceHighQualityInterpolation)
    }

    @MainActor func testPersistenceRoundTrip() {
        let d = makeDefaults()
        let s = AppSettings(defaults: d)
        s.language = .japanese
        s.photoSortOrder = .modificationDate
        s.paintInitialColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        s.saveJPEGQuality = 0.5
        s.slideshowShuffle = true
        let t = AppSettings(defaults: d)
        XCTAssertEqual(t.language, .japanese)
        XCTAssertEqual(t.photoSortOrder, .modificationDate)
        XCTAssertEqual(t.paintInitialColor.hexRGBA, "#FF0000FF")
        XCTAssertEqual(t.saveJPEGQuality, 0.5)
        XCTAssertTrue(t.slideshowShuffle)
    }

    @MainActor func testResetToDefaults() {
        let s = AppSettings(defaults: makeDefaults())
        s.paintUndoLevels = 10; s.slideshowLoop = false; s.performancePreset = .lowMemory
        s.resetToDefaults()
        XCTAssertEqual(s.paintUndoLevels, 50)
        XCTAssertTrue(s.slideshowLoop)
        XCTAssertEqual(s.performancePreset, .automatic)
        XCTAssertEqual(s.performanceCacheMB, 512)
    }

    @MainActor func testLanguageResolution() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["ja"]), "ja")
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: []), "en")
        XCTAssertEqual(AppLanguage.resolve(.japanese, preferred: ["en"]), "ja")
        XCTAssertEqual(AppLanguage.resolve(.english, preferred: ["ja-JP"]), "en")
    }

    @MainActor func testShortcutRendering() {
        XCTAssertEqual(ShortcutCatalog.display(key: "s", modifiers: [.command, .shift]), "⇧⌘S")
        XCTAssertEqual(ShortcutCatalog.display(key: "c", modifiers: [.command, .option, .shift, .control]), "⌃⌥⇧⌘C")
        XCTAssertEqual(ShortcutCatalog.keyName(String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)), "←")
    }

    @MainActor func testShortcutCatalogReadsMenuRecursively() {
        let main = NSMenu()
        let top = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); let file = NSMenu(title: "File")
        file.addItem(NSMenuItem(title: "Save", action: nil, keyEquivalent: "s"))
        let sub = NSMenuItem(title: "More", action: nil, keyEquivalent: ""); let subMenu = NSMenu(title: "More")
        subMenu.addItem(NSMenuItem(title: "Deep", action: nil, keyEquivalent: "d"))
        sub.submenu = subMenu; file.addItem(sub); file.addItem(.separator())
        file.addItem(NSMenuItem(title: "NoKey", action: nil, keyEquivalent: ""))
        top.submenu = file; main.addItem(top)
        let entries = ShortcutCatalog.entries(menu: main)
        XCTAssertTrue(entries.contains { $0.title == "Save" && $0.keys == "⌘S" && $0.section == "File" })
        XCTAssertTrue(entries.contains { $0.title == "Deep" && $0.keys == "⌘D" })
        XCTAssertFalse(entries.contains { $0.title == "NoKey" })
        XCTAssertTrue(entries.contains { $0.keys == "X" })  // canvas-only entries present
    }
}
