import XCTest
@testable import DosPhotoPaint

/// Verifies the compiled Japanese localization of every String Catalog table.
/// Catalog keys are produced from the compiler-extracted keys by `tools/l10n_sync.py`.
@MainActor
final class LocalizationTests: XCTestCase {
    static let tables = ["Menu", "Toolbar", "Paint", "Viewer", "Settings", "Window", "Documents", "InfoPlist"]

    /// Keys that are legitimately identical in Japanese.
    static let identicalKeys: Set<String> = ["DosPhotoPaint", "PNG", "JPEG", "HEIC", "TIFF", "BMP", "px", "%", "OK", "ISO",
                                             "16:9", "4:3", "1:1", "RGB %lld, %lld, %lld",
                                             "%lld × %lld px", "%lld × %lld px  →  %lld × %lld px"]

    private func lproj(_ code: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: code, ofType: "lproj"), "\(code).lproj missing from the app bundle")
        return try XCTUnwrap(Bundle(path: path))
    }

    private func table(_ name: String, in bundle: Bundle) throws -> [String: String] {
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "strings"), "\(name).strings missing in \(bundle.bundlePath)")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// Format specifiers in order of kind (positional indices ignored), e.g. ["@", "lld"].
    private func specifiers(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:[0-9]+\\$)?(@|lld|ld|d|lf|f|s)")
        let ns = s as NSString
        let found = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .map { (m: NSTextCheckingResult) -> (Int, String) in
                let full = ns.substring(with: m.range)
                let kind = ns.substring(with: m.range(at: 1))
                let pos = full.contains("$") ? Int(full.dropFirst().prefix { $0 != "$" }) ?? 0 : 0
                return (pos, kind)
            }
        return found.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    func testBundleDeclaresJapanese() {
        let localizations = Bundle.main.localizations
        XCTAssertTrue(localizations.contains("ja"))
        XCTAssertTrue(localizations.contains("en"))
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
    }

    func testEveryKeyHasJapaneseTranslation() throws {
        let ja = try lproj("ja"), en = try lproj("en")
        for name in Self.tables {
            let keys = try table(name, in: en)
            let translated = try table(name, in: ja)
            XCTAssertFalse(keys.isEmpty, "\(name) has no keys")
            for key in keys.keys {
                guard let value = translated[key], !value.isEmpty else {
                    XCTFail("[\(name)] no Japanese value for “\(key)”"); continue
                }
                if value == key, !Self.identicalKeys.contains(key) {
                    XCTFail("[\(name)] Japanese value identical to key “\(key)”")
                }
            }
        }
    }

    func testFormatSpecifiersMatch() throws {
        let ja = try lproj("ja"), en = try lproj("en")
        var checked = 0
        for name in Self.tables {
            let keys = try table(name, in: en)
            let translated = try table(name, in: ja)
            for key in keys.keys {
                guard let value = translated[key] else { continue }
                XCTAssertEqual(specifiers(key), specifiers(value), "[\(name)] specifiers differ for “\(key)” -> “\(value)”")
                if !specifiers(key).isEmpty { checked += 1 }
            }
        }
        XCTAssertGreaterThan(checked, 15)
    }

    func testSpotChecks() throws {
        let ja = try lproj("ja")
        func s(_ key: String, _ table: String) -> String {
            ja.localizedString(forKey: key, value: "<missing>", table: table)
        }
        let expectations: [(String, String, String)] = [
            ("File", "Menu", "ファイル"), ("Edit", "Menu", "編集"), ("View", "Menu", "表示"),
            ("Image", "Menu", "画像"), ("Tools", "Menu", "ツール"), ("Window", "Menu", "ウインドウ"),
            ("Help", "Menu", "ヘルプ"), ("Layer", "Menu", "レイヤー"),
            ("Open…", "Menu", "開く…"), ("Save…", "Menu", "保存…"), ("Save As…", "Menu", "別名で保存…"),
            ("Export…", "Menu", "書き出す…"), ("Duplicate", "Menu", "複製"), ("Undo", "Menu", "元に戻す"),
            ("Redo", "Menu", "やり直す"), ("Cut", "Menu", "カット"), ("Copy", "Menu", "コピー"),
            ("Paste", "Menu", "ペースト"), ("Select All", "Menu", "すべてを選択"),
            ("Zoom In", "Menu", "拡大"), ("Zoom Out", "Menu", "縮小"), ("Actual Size (100%)", "Menu", "実際のサイズ (100%)"),
            ("Zoom to Fit", "Menu", "ウインドウに合わせる"), ("Enter Full Screen", "Menu", "フルスクリーンにする"),
            ("Slideshow", "Menu", "スライドショー"), ("Image Info", "Menu", "情報を見る"),
            ("Resize Image…", "Menu", "画像サイズを変更…"), ("Canvas Size…", "Menu", "キャンバスサイズ…"),
            ("Photo", "Toolbar", "フォト"), ("Paint", "Toolbar", "ペイント"),
            ("Eraser", "Paint", "消しゴム"), ("Eyedropper", "Paint", "スポイト"), ("Brush", "Paint", "ブラシ"),
            ("Pen", "Paint", "ペン"), ("Opacity", "Paint", "不透明度"), ("Layers", "Paint", "レイヤー"),
            ("Language", "Settings", "言語"), ("Photo", "Settings", "フォト"), ("Paint", "Settings", "ペイント")
        ]
        for (key, table, expected) in expectations {
            XCTAssertEqual(s(key, table), expected, "[\(table)] \(key)")
        }
        XCTAssertEqual(String(format: s("About %@", "Menu"), "DosPhotoPaint"), "DosPhotoPaintについて")
        XCTAssertEqual(String(format: s("Image %lld of %lld", "Window"), 3, 10), "10枚中3枚目の画像")
    }

    func testEnglishFallbackKeepsKeys() throws {
        let en = try lproj("en")
        XCTAssertEqual(en.localizedString(forKey: "Open…", value: nil, table: "Menu"), "Open…")
        XCTAssertEqual(en.localizedString(forKey: "File", value: nil, table: "Menu"), "File")
    }

    func testInfoPlistDocumentTypeNamesAreLocalized() throws {
        let ja = try table("InfoPlist", in: try lproj("ja"))
        XCTAssertEqual(ja["PNG image"], "PNG画像")
        XCTAssertEqual(ja["DosPhotoPaint Project"], "DosPhotoPaintプロジェクト")
    }
}
