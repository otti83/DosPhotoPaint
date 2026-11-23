import XCTest
@testable import DosPhotoPaint

final class SmokeTests: XCTestCase {
    func testLanguageResolution() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["ja-JP", "en-US"]), "ja")
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["fr-FR", "ja-JP"]), "en")
        XCTAssertEqual(AppLanguage.resolve(.english, preferred: ["ja-JP"]), "en")
        XCTAssertEqual(AppLanguage.resolve(.japanese, preferred: ["en-US"]), "ja")
    }
}
