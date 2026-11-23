import AppKit

/// Printing: a view that draws the flattened image centred and fitted to the printable area.
/// Scaling and orientation come from the standard print/page-setup panels (`NSPrintInfo`).
extension ImageDocument {

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let image = try imageForPrinting()
        // swiftlint:disable:next force_cast
        let info = printInfo.copy() as! NSPrintInfo
        for (key, value) in printSettings { info.dictionary()[key] = value }
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true

        let paper = info.paperSize  // already reflects the chosen orientation
        let printable = NSSize(width: max(1, paper.width - info.leftMargin - info.rightMargin),
                               height: max(1, paper.height - info.topMargin - info.bottomMargin))
        let view = ImagePrintView(image: image, size: printable)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = displayName
        operation.showsPrintPanel = true
        return operation
    }

    /// Flattened visible image; an unmaterialized image is decoded in full (printing is synchronous).
    private func imageForPrinting() throws -> CGImage {
        if let canvas {
            canvas.commitFloatingIfNeeded()
            guard let flat = canvas.flattenedImage() else { throw CocoaError(.fileReadUnknown) }
            return flat
        }
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        return try ImageLoader.loadFullImage(url: url).image
    }
}

/// Draws one image fitted (aspect preserved, no upscale limit) into the page and centred.
final class ImagePrintView: NSView {
    private let image: NSImage
    private let pixelSize: CGSize

    init(image: CGImage, size: NSSize) {
        pixelSize = CGSize(width: image.width, height: image.height)
        self.image = NSImage(cgImage: image, size: pixelSize)
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// Aspect-fit rectangle of the image inside the view.
    var imageRect: NSRect {
        let scale = min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
        let w = pixelSize.width * scale, h = pixelSize.height * scale
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
