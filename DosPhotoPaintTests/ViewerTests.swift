import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DosPhotoPaint

@MainActor
final class ViewerTests: AppTestCase {
    private func urls(_ names: [String]) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/viewer-test/\($0)") } }

    // MARK: Sorting

    func testNaturalSort() {
        let input = urls(["img10.jpg", "img2.jpg", "img1.jpg", "Img3.jpg"])
        let sorted = BrowsingSession.sorted(input, by: .naturalName).map(\.lastPathComponent)
        XCTAssertEqual(sorted, ["img1.jpg", "img2.jpg", "Img3.jpg", "img10.jpg"])
    }

    func testPlainNameSortIsNotNatural() {
        let sorted = BrowsingSession.sorted(urls(["img10.jpg", "img2.jpg"]), by: .name).map(\.lastPathComponent)
        XCTAssertEqual(sorted, ["img10.jpg", "img2.jpg"])
    }

    // MARK: Session

    func testSteppingWithoutAndWithLoop() {
        let list = urls(["a.png", "b.png", "c.png"])
        let s = BrowsingSession(explicitURLs: list)
        s.didShow(list[0])
        XCTAssertEqual(s.position?.index, 1)
        XCTAssertNil(s.url(movingBy: -1, loop: false))
        XCTAssertEqual(s.url(movingBy: -1, loop: true), list[2])
        XCTAssertEqual(s.url(movingBy: 1, loop: false), list[1])
        s.didShow(list[2])
        XCTAssertNil(s.url(movingBy: 1, loop: false))
        XCTAssertEqual(s.url(movingBy: 1, loop: true), list[0])
        XCTAssertEqual(s.position?.count, 3)
    }

    func testSingleImageSessionNeverSteps() {
        let a = urls(["only.png"])[0]
        let s = BrowsingSession(explicitURLs: nil)
        s.replace(with: [a], current: a)
        XCTAssertNil(s.url(movingBy: 1, loop: true))
        XCTAssertNil(s.url(movingBy: -1, loop: true))
        XCTAssertEqual(s.position?.index, 1)
    }

    func testRemoveKeepsPosition() {
        let list = urls(["a.png", "b.png", "c.png", "d.png"])
        let s = BrowsingSession(explicitURLs: list)
        s.didShow(list[2])
        // Removing an earlier image shifts the index but keeps the current image.
        XCTAssertEqual(s.remove(list[0]), list[2])
        XCTAssertEqual(s.currentURL, list[2])
        XCTAssertEqual(s.position?.index, 2)
        // Removing the current image selects its successor.
        XCTAssertEqual(s.remove(list[2]), list[3])
        // Removing the last image selects the new last one.
        XCTAssertEqual(s.remove(list[3]), list[1])
        XCTAssertEqual(s.remove(list[1]), nil)
        XCTAssertNil(s.currentIndex)
    }

    // MARK: Slideshow shuffle & preloading

    func testShuffleShowsEveryImageOncePerRound() {
        let list = urls(["a", "b", "c", "d", "e"])
        var shuffle = SlideshowShuffle(current: list[0])
        var rng = SystemRandomNumberGenerator()
        var seen: [URL] = []
        var current: URL? = list[0]
        while let next = shuffle.next(all: list, current: current, loop: false, using: &rng) {
            seen.append(next); current = next
        }
        XCTAssertEqual(Set(seen), Set(list.dropFirst()))
        XCTAssertEqual(seen.count, 4)
    }

    func testShuffleLoopsAndNeverRepeatsCurrentImmediately() {
        let list = urls(["a", "b", "c"])
        var shuffle = SlideshowShuffle(current: list[0])
        var rng = SystemRandomNumberGenerator()
        var current: URL? = list[0]
        for _ in 0..<30 {
            let next = shuffle.next(all: list, current: current, loop: true, using: &rng)
            XCTAssertNotNil(next)
            XCTAssertNotEqual(next, current)
            current = next
        }
    }

    func testPreloadNeighbours() {
        let list = urls(["a", "b", "c", "d", "e"])
        XCTAssertEqual(ImagePreloader.neighbours(of: 2, in: list, count: 1, loop: false), [list[3], list[1]])
        XCTAssertEqual(ImagePreloader.neighbours(of: 0, in: list, count: 2, loop: false), [list[1], list[2]])
        XCTAssertEqual(ImagePreloader.neighbours(of: 0, in: list, count: 1, loop: true), [list[1], list[4]])
        XCTAssertEqual(ImagePreloader.neighbours(of: 1, in: list, count: 0, loop: true), [])
        XCTAssertEqual(ImagePreloader.neighbours(of: 0, in: Array(list.prefix(2)), count: 5, loop: true), [list[1]])
    }

    func testHighResolutionRequirement() {
        // 6000x4000 shown from a 2000px preview.
        XCTAssertNil(ViewerCoordinator.requiredLongestEdge(imageLongest: 2000, fullLongest: 6000, fullShortest: 4000, magnification: 0.3, backingScale: 1))
        XCTAssertEqual(ViewerCoordinator.requiredLongestEdge(imageLongest: 2000, fullLongest: 6000, fullShortest: 4000, magnification: 1, backingScale: 1), 6000)
        XCTAssertEqual(ViewerCoordinator.requiredLongestEdge(imageLongest: 2000, fullLongest: 6000, fullShortest: 4000, magnification: 0.5, backingScale: 2), 6000)
        XCTAssertNil(ViewerCoordinator.requiredLongestEdge(imageLongest: 6000, fullLongest: 6000, fullShortest: 4000, magnification: 8, backingScale: 2))
        // Memory cap for huge images.
        let capped = ViewerCoordinator.requiredLongestEdge(imageLongest: 4000, fullLongest: 20000, fullShortest: 10000, magnification: 1, backingScale: 1)
        XCTAssertNotNil(capped)
        XCTAssertLessThan(capped!, 20000)
    }

    func testMissingFileDetection() {
        XCTAssertTrue(ViewerCoordinator.isMissing(URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID().uuidString).png")))
        XCTAssertFalse(ViewerCoordinator.isMissing(URL(fileURLWithPath: "/tmp")))
    }

    // MARK: Metadata

    private func makeImage(_ properties: [CFString: Any], type: UTType = .jpeg) throws -> URL {
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meta-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "img")")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMetadataWithExifAndGPS() throws {
        let url = try makeImage([
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 0.004,
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifISOSpeedRatings: [200],
                kCGImagePropertyExifFocalLength: 50,
                kCGImagePropertyExifDateTimeOriginal: "2024:05:06 07:08:09",
                kCGImagePropertyExifLensModel: "Test Lens 50mm",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "ACME", kCGImagePropertyTIFFModel: "Cam 1"],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 35.5, kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 139.25, kCGImagePropertyGPSLongitudeRef: "E",
                kCGImagePropertyGPSAltitude: 12.5, kCGImagePropertyGPSAltitudeRef: 0,
            ],
        ])
        let m = try XCTUnwrap(ImageMetadata.read(from: url))
        XCTAssertEqual(m.pixelWidth, 40)
        XCTAssertEqual(m.pixelHeight, 20)
        XCTAssertEqual(m.pixelCount, 800)
        XCTAssertEqual(m.cameraMake, "ACME")
        XCTAssertEqual(m.cameraModel, "Cam 1")
        XCTAssertEqual(m.lensModel, "Test Lens 50mm")
        XCTAssertEqual(try XCTUnwrap(m.exposureTime), 0.004, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(m.fNumber), 2.8, accuracy: 1e-6)
        XCTAssertEqual(m.iso, 200)
        XCTAssertEqual(try XCTUnwrap(m.focalLength), 50, accuracy: 1e-6)
        let taken = try XCTUnwrap(m.dateTaken)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: taken)
        XCTAssertEqual([comps.year, comps.month, comps.day, comps.hour, comps.minute, comps.second], [2024, 5, 6, 7, 8, 9])
        XCTAssertEqual(try XCTUnwrap(m.latitude), -35.5, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(m.longitude), 139.25, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(m.altitude), 12.5, accuracy: 1e-6)
        XCTAssertTrue(m.hasGPS)
        XCTAssertGreaterThan(m.fileSize ?? 0, 0)
        XCTAssertEqual(m.fileName, url.lastPathComponent)
    }

    func testMetadataNeverFabricatesMissingFields() throws {
        let url = try makeImage([:], type: .png)
        let m = try XCTUnwrap(ImageMetadata.read(from: url))
        XCTAssertEqual(m.pixelWidth, 40)
        XCTAssertNil(m.cameraMake)
        XCTAssertNil(m.cameraModel)
        XCTAssertNil(m.lensModel)
        XCTAssertNil(m.exposureTime)
        XCTAssertNil(m.fNumber)
        XCTAssertNil(m.iso)
        XCTAssertNil(m.focalLength)
        XCTAssertNil(m.dateTaken)
        XCTAssertFalse(m.hasGPS)
        XCTAssertFalse(m.hasExposureInfo)
        XCTAssertTrue(m.hasAlpha)
    }

    func testMetadataSwapsDimensionsForRotatedOrientation() throws {
        let url = try makeImage([kCGImagePropertyOrientation: 6])
        let m = try XCTUnwrap(ImageMetadata.read(from: url))
        XCTAssertEqual(m.pixelWidth, 20)
        XCTAssertEqual(m.pixelHeight, 40)
    }

    func testMetadataOfNonImageIsNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notimage-\(UUID().uuidString).txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(ImageMetadata.read(from: url))
    }
}
