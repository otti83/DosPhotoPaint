import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import DosPhotoPaint

/// GIF playback: always loops (even "play once" files), frame stepping, delays.
@MainActor
final class AnimationPlayerTests: AppTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("anim-\(UUID().uuidString).gif")
        // 3 frames (red, green, blue), 20 ms each, loop count 1 = "play once".
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 3, nil))
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 1]] as CFDictionary)
        for rgb in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)] {
            let b = RasterBuffer(width: 16, height: 16, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
            b.fill(CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
            CGImageDestinationAddImage(dest, b.copyImage()!,
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.02]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: url) }

    private func wait(_ what: String, timeout: TimeInterval = 10, _ condition: () -> Bool) async {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "Timed out waiting for: \(what)")
    }

    func testPlayOnceGIFKeepsLoopingAndNeverStops() async {
        let player = AnimationPlayer()
        var shown = 0
        player.play(url: url, maxPixelSize: 64) { _ in shown += 1 }
        await wait("frames loaded") { player.frameCount == 3 }
        // A "play once" file has 3 frames; well past several cycles we are still delivering frames.
        await wait("several loops", timeout: 15) { shown >= 9 }
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.isPaused)
        player.stop()
        XCTAssertEqual(player.frameCount, 0)
    }

    func testShowFramePausesOnThatFrame() async {
        let player = AnimationPlayer()
        var last: CGImage?
        player.play(url: url, maxPixelSize: 64) { last = $0 }
        await wait("frames loaded") { player.frameCount == 3 }
        player.show(frame: 2)
        XCTAssertTrue(player.isPaused)
        XCTAssertEqual(player.currentFrame, 2)
        await wait("frame 2 shown") {
            guard let last, let px = RasterBuffer(image: last)?.pixel(x: 8, y: 8) else { return false }
            return px.b > 200 && px.r < 50   // blue = third frame
        }
        player.step(by: 1)
        XCTAssertEqual(player.currentFrame, 0, "stepping wraps around")
        player.togglePause()
        XCTAssertFalse(player.isPaused)
        player.stop()
    }

    func testDelayNormalization() {
        XCTAssertEqual(AnimationPlayer.normalizedDelay(nil), 0.1)
        XCTAssertEqual(AnimationPlayer.normalizedDelay(0), 0.1)
        XCTAssertEqual(AnimationPlayer.normalizedDelay(0.01), 0.1, "browser convention for tiny delays")
        XCTAssertEqual(AnimationPlayer.normalizedDelay(0.05), 0.05)
    }

    func testBrowserThumbnailSizeIsClampedAndReset() {
        let suite = "DosPhotoPaint.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: d)
        XCTAssertEqual(s.photoBrowserThumbnailSize, 140)
        s.photoBrowserThumbnailSize = 5000
        XCTAssertEqual(s.photoBrowserThumbnailSize, AppSettings.browserThumbnailRange.upperBound)
        s.resetToDefaults()
        XCTAssertEqual(s.photoBrowserThumbnailSize, 140)
    }
}
