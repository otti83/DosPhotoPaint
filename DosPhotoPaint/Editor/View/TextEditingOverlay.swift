import AppKit

/// Layout constants shared by the live editor (`EditorTextView`) and the committed rendering
/// (`TextRenderer`). Both use the same values so wrapping is identical.
enum TextLayoutMetrics {
    /// Padding between box border and text (image pixels).
    static let inset = NSSize(width: 4, height: 2)
    static let linePadding: CGFloat = 2

    /// A TextKit 1 stack (explicit, so `layoutManager` access never triggers a TextKit 2 downgrade).
    static func makeStack(boxWidth: CGFloat) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: max(1, boxWidth - 2 * inset.width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = linePadding
        layout.addTextContainer(container)
        return (storage, layout, container)
    }
}

/// The real `NSTextView` that hosts text editing (IME marked text is handled by AppKit).
/// It lives inside `CanvasView`, in image pixel space, so it scales with the zoom.
final class EditorTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onChange: (() -> Void)?
    var onFontPanelChange: ((NSFont) -> Void)?
    /// Returns true for points (in the superview's coordinates) that belong to the box border,
    /// so the canvas receives drags that move/resize the box.
    var isBorderPoint: ((CGPoint) -> Bool)?

    /// Separate from the canvas undo stack: text-view undo never touches canvas undo.
    private let textUndoManager = UndoManager()
    /// NSLayoutManager does not retain its text storage; the view must keep the stack alive.
    private let ownedStorage: NSTextStorage
    override var undoManager: UndoManager? { textUndoManager }

    override init(frame: CGRect) {
        let (storage, _, container) = TextLayoutMetrics.makeStack(boxWidth: frame.width)
        ownedStorage = storage
        super.init(frame: frame, textContainer: container)
        container.widthTracksTextView = true
        isRichText = true
        allowsUndo = true
        drawsBackground = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        textContainerInset = TextLayoutMetrics.inset
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        usesFontPanel = true
        setAccessibilityLabel(String(localized: "Text box", table: "Paint"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isBorderPoint?(point) == true { return nil }
        return super.hitTest(point)
    }

    override func keyDown(with event: NSEvent) {
        // While the IME has marked text, every key (Return, Escape…) belongs to the IME.
        if !hasMarkedText() {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if (event.keyCode == 36 || event.keyCode == 76), mods.contains(.command) {  // ⌘Return
                onCommit?()
                return
            }
            if event.keyCode == 53, mods.subtracting([.capsLock, .function]).isEmpty {  // Escape
                onCancel?()
                return
            }
        }
        super.keyDown(with: event)
    }

    /// Edit > Undo/Redo while editing act on the text view's private undo stack (never the canvas).
    @objc(undo:) func undoText(_ sender: Any?) { textUndoManager.undo(); onChange?() }
    @objc(redo:) func redoText(_ sender: Any?) { textUndoManager.redo(); onChange?() }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case Selector(("undo:")): return textUndoManager.canUndo
        case Selector(("redo:")): return textUndoManager.canRedo
        default: return super.validateUserInterfaceItem(item)
        }
    }

    /// A text box has a single style (the tool options): pasted text never brings its own
    /// fonts, colours or attachments.
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func didChangeText() {
        super.didChangeText()
        onChange?()
    }

    /// Font panel (⌘T) → handled here so the whole text changes, not just the selection.
    override func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        onFontPanelChange?(manager.convert(font ?? NSFont.systemFont(ofSize: 12)))
    }
}

/// Renders an attributed string into a layer context so the result matches the live text view.
enum TextRenderer {
    /// Draws `text` in `box` (image pixels) into `ctx`, whose user space is y-down pixels.
    /// Wrapping width, insets and line padding equal those of `EditorTextView`. Clipped to `box`.
    static func draw(_ text: NSAttributedString, in box: CGRect, into ctx: CGContext) {
        let (storage, layout, container) = TextLayoutMetrics.makeStack(boxWidth: box.width)
        storage.setAttributedString(text)
        let glyphs = layout.glyphRange(for: container)
        ctx.saveGState()
        ctx.clip(to: box)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let origin = CGPoint(x: box.minX + TextLayoutMetrics.inset.width, y: box.minY + TextLayoutMetrics.inset.height)
        layout.drawBackground(forGlyphRange: glyphs, at: origin)
        layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    /// Height needed to show `text` at the given box width.
    static func requiredHeight(for text: NSAttributedString, boxWidth: CGFloat) -> CGFloat {
        let (storage, layout, container) = TextLayoutMetrics.makeStack(boxWidth: boxWidth)
        storage.setAttributedString(text)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height + 2 * TextLayoutMetrics.inset.height)
    }
}
