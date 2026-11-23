// Builds AppIcon.appiconset from the master artwork in icon/icon.png.
//
// The artwork is full-bleed square. macOS app icons use a rounded-square ("squircle") plate
// of 824×824 on a 1024×1024 canvas (100 px margin) with a soft drop shadow, so the artwork is
// scaled into that plate, clipped with a continuous-corner rounded rect, and every required
// size is rendered from the 1024 master with high-quality resampling.
//
// Usage: swiftc -O tools/make_icon.swift -o /tmp/make_icon && /tmp/make_icon icon/icon.png DosPhotoPaint/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("usage: make_icon <source.png> <AppIcon.appiconset>") }
let source = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(source.path)") }

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// 1024 master.
let canvas = 1024
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185  // Apple macOS icon template corner radius for an 824 plate
let master = context(canvas)
master.interpolationQuality = .high
let platePath = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius).cgPath

// Drop shadow under the plate.
master.saveGState()
master.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.32))
master.addPath(platePath)
master.setFillColor(CGColor(gray: 0, alpha: 1))
master.fillPath()
master.restoreGState()

// Artwork clipped to the plate (covers the plate; source is square so no distortion).
master.saveGState()
master.addPath(platePath)
master.clip()
master.draw(art, in: plate)
master.restoreGState()

// Thin inner edge highlight for definition on dark Docks.
master.saveGState()
master.addPath(platePath)
master.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
master.setLineWidth(2)
master.strokePath()
master.restoreGState()

let masterImage = master.makeImage()!

func write(_ image: CGImage, _ name: String) {
    let url = output.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed \(name)") }
}

func resized(_ px: Int) -> CGImage {
    if px == canvas { return masterImage }
    let c = context(px)
    c.interpolationQuality = .high
    c.draw(masterImage, in: CGRect(x: 0, y: 0, width: px, height: px))
    return c.makeImage()!
}

var entries: [String] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    write(resized(points * scale), name)
    entries.append("""
        { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
    """)
}
let json = "{\n  \"images\" : [\n" + entries.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! json.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(entries.count) icons to \(output.path)")
