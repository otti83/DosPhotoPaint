import AppKit

/// Font families offered by the Text options. The system font's family is a private
/// ".AppleSystemUIFont"; it is shown as a localized "System Font" entry listed first, followed by the
/// real installed families (dot-prefixed private families are never listed).
enum FontFamilies {
    struct Entry: Hashable, Identifiable {
        /// Family name as used by NSFontManager (the system entry uses the system font's family).
        let family: String
        let displayName: String
        var id: String { family }
    }

    static var systemFamily: String { NSFont.systemFont(ofSize: 12).familyName ?? ".AppleSystemUIFont" }

    static var systemDisplayName: String { String(localized: "System Font", table: "Paint") }

    static func isSystem(family: String) -> Bool { family.hasPrefix(".") }

    /// Human-readable, localized name for a family.
    static func displayName(forFamily family: String) -> String {
        if isSystem(family: family) { return systemDisplayName }
        return NSFontManager.shared.localizedName(forFamily: family, face: nil)
    }

    /// System font first, then real families sorted as the font manager lists them.
    static func entries() -> [Entry] {
        let real = NSFontManager.shared.availableFontFamilies.filter { !isSystem(family: $0) }
        return [Entry(family: systemFamily, displayName: systemDisplayName)]
            + real.map { Entry(family: $0, displayName: displayName(forFamily: $0)) }
    }

    /// Entry for the family of the PostScript font `fontName` (system entry for the system font).
    static func family(forFontName fontName: String) -> String {
        NSFont(name: fontName, size: 12)?.familyName ?? systemFamily
    }

    /// PostScript name of the regular face of `family`, or nil if it has none.
    static func fontName(forFamily family: String) -> String? {
        if isSystem(family: family) { return NSFont.systemFont(ofSize: 12).fontName }
        return NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12)?.fontName
    }
}
