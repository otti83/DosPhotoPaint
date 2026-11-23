import XCTest
import AppKit
@testable import DosPhotoPaint

/// Every menu item with an action must be reachable: some class in the responder chain
/// (window controller, document, app delegate, document controller, window, app, text) has to
/// implement it, otherwise the item is permanently disabled.
@MainActor
final class MenuValidationTests: AppTestCase {
    private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            [item] + (item.submenu.map(allItems) ?? [])
        }
    }

    func testEveryMenuActionHasAnImplementer() {
        let menu = MainMenu.build()
        let implementers: [AnyClass] = [
            MainWindowController.self, AppDelegate.self, ImageDocument.self, DocumentController.self,
            NSWindow.self, NSApplication.self, NSText.self, NSFontManager.self,
        ]
        var missing: [String] = []
        for item in allItems(menu) {
            guard let action = item.action else { continue }
            if item.target != nil { continue }
            let ok = implementers.contains { ($0 as? NSObject.Type)?.instancesRespond(to: action) == true }
            if !ok { missing.append("\(item.title) -> \(action)") }
        }
        XCTAssertTrue(missing.isEmpty, "Menu items without implementer: \(missing)")
    }

    func testMenuKeyEquivalentsAreUnique() {
        let menu = MainMenu.build()
        var seen: [String: String] = [:]
        for item in allItems(menu) where !item.keyEquivalent.isEmpty {
            let key = "\(item.keyEquivalentModifierMask.rawValue)-\(item.keyEquivalent)"
            if let other = seen[key], !(item.isHidden || item.title == other) {
                XCTFail("Duplicate key equivalent \(key): \(item.title) vs \(other)")
            }
            seen[key] = item.title
        }
    }

    func testRequiredShortcutsExist() {
        let items = allItems(MainMenu.build())
        func has(_ key: String, _ mods: NSEvent.ModifierFlags) -> Bool {
            items.contains { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == mods }
        }
        for (k, m) in [("n", NSEvent.ModifierFlags.command), ("o", .command), ("s", .command), ("s", [.command, .shift]),
                       ("w", .command), ("z", .command), ("z", [.command, .shift]), ("c", .command), ("v", .command),
                       ("x", .command), ("a", .command), ("0", .command), ("1", .command), ("-", .command),
                       (",", .command), ("p", .command)] {
            XCTAssertTrue(has(k, m), "missing ⌘ shortcut \(k)")
        }
    }
}

@MainActor
final class MenuStateTests: AppTestCase {
    func testToolbarToggleIsImplementedAndFontMenuHasTarget() {
        let items = MainMenu.build().items.flatMap { $0.submenu?.items ?? [] }
        let toolbar = items.first { $0.action == #selector(AppActions.toggleToolbar(_:)) }
        XCTAssertNotNil(toolbar)
        XCTAssertTrue(MainWindowController.instancesRespond(to: #selector(AppActions.toggleToolbar(_:))))
        let fonts = items.first { $0.action == #selector(NSFontManager.orderFrontFontPanel(_:)) }
        XCTAssertTrue(fonts?.target === NSFontManager.shared)
    }
}
