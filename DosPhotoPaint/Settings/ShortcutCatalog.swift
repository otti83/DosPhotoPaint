import AppKit

struct ShortcutEntry: Identifiable, Hashable {
    let id = UUID()
    let section: String
    let title: String
    let keys: String
}

/// Builds the list of keyboard shortcuts shown in Settings. Menu shortcuts are read from the
/// live main menu so the list can never go stale; canvas-only keys are listed explicitly.
enum ShortcutCatalog {
    private static func s(_ key: String.LocalizationValue) -> String { String(localized: key, table: "Settings") }

    static func entries(menu: NSMenu? = NSApp.mainMenu) -> [ShortcutEntry] {
        var result: [ShortcutEntry] = []
        if let menu {
            for item in menu.items {
                guard let sub = item.submenu else { continue }
                collect(sub, section: sub.title, into: &result)
            }
        }
        result.append(contentsOf: canvasEntries())
        return result
    }

    static func collect(_ menu: NSMenu, section: String, into result: inout [ShortcutEntry]) {
        for item in menu.items where !item.isSeparatorItem {
            if let sub = item.submenu {
                collect(sub, section: section, into: &result)
            } else if !item.keyEquivalent.isEmpty, !item.isHidden, !item.isAlternate {
                result.append(ShortcutEntry(section: section, title: item.title,
                                            keys: display(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)))
            }
        }
    }

    /// Modifier symbols in the standard macOS order (⌃⌥⇧⌘) followed by the key.
    static func display(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        return out + keyName(key)
    }

    static func keyName(_ key: String) -> String {
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else { return key.uppercased() }
        switch Int(scalar.value) {
        case 0x08, 0x7F: return "⌫"
        case 0x0D, 0x03: return "↩"
        case 0x09: return "⇥"
        case 0x1B: return "⎋"
        case 0x20: return s("Space")
        case NSUpArrowFunctionKey: return "↑"
        case NSDownArrowFunctionKey: return "↓"
        case NSLeftArrowFunctionKey: return "←"
        case NSRightArrowFunctionKey: return "→"
        case NSHomeFunctionKey: return "↖"
        case NSEndFunctionKey: return "↘"
        case NSPageUpFunctionKey: return "⇞"
        case NSPageDownFunctionKey: return "⇟"
        case NSDeleteFunctionKey: return "⌦"
        case NSF1FunctionKey...NSF12FunctionKey: return "F\(Int(scalar.value) - NSF1FunctionKey + 1)"
        default: return key.uppercased()
        }
    }

    static func canvasEntries() -> [ShortcutEntry] {
        let paint = s("Paint Canvas")
        let photo = s("Photo Canvas")
        var list: [ShortcutEntry] = []
        for tool in ToolKind.allCases {
            if let key = tool.shortcutKey {
                list.append(ShortcutEntry(section: paint, title: tool.localizedName, keys: key.uppercased()))
            }
        }
        list += [
            ShortcutEntry(section: paint, title: s("Swap Foreground / Background Colors"), keys: "X"),
            ShortcutEntry(section: paint, title: s("Increase Tool Size"), keys: "]"),
            ShortcutEntry(section: paint, title: s("Decrease Tool Size"), keys: "["),
            ShortcutEntry(section: paint, title: s("Pan Temporarily (hold)"), keys: s("Space")),
            ShortcutEntry(section: paint, title: s("Delete Selection"), keys: "⌫"),
            ShortcutEntry(section: paint, title: s("Cancel / Leave Full Screen"), keys: "⎋"),
            ShortcutEntry(section: photo, title: s("Previous Image"), keys: "←"),
            ShortcutEntry(section: photo, title: s("Next Image"), keys: "→"),
            ShortcutEntry(section: photo, title: s("First Image"), keys: "Home"),
            ShortcutEntry(section: photo, title: s("Last Image"), keys: "End"),
            ShortcutEntry(section: photo, title: s("Pause / Resume Slideshow"), keys: s("Space")),
            ShortcutEntry(section: photo, title: s("Stop Slideshow / Leave Full Screen"), keys: "⎋"),
        ]
        return list
    }
}
