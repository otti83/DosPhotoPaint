import AppKit

extension MainWindowController {
    /// Font panel (⌘T) with no text box being edited: remember the choice as the text tool font.
    /// (While a box is edited, `EditorTextView.changeFont(_:)` handles it first.)
    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        let font = manager.convert(TextTool.font(for: toolSettings))
        let traits = manager.traits(of: font)
        toolSettings.fontName = font.fontName
        toolSettings.fontSize = min(max(Double(font.pointSize), ToolSettings.fontSizeRange.lowerBound), ToolSettings.fontSizeRange.upperBound)
        toolSettings.bold = traits.contains(.boldFontMask)
        toolSettings.italic = traits.contains(.italicFontMask)
    }
}
