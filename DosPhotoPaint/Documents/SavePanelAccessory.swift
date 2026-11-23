import AppKit
import UniformTypeIdentifiers

/// Accessory for save/export panels: optional format popup (export only — NSDocument supplies its
/// own for Save As) plus a quality slider that is only active for lossy formats (JPEG/HEIC).
final class SavePanelAccessory: NSObject {
    let view = NSStackView()
    /// Quality 0…1 as chosen by the user.
    private(set) var quality: Double
    private weak var panel: NSSavePanel?
    private let slider = NSSlider(value: 0.9, minValue: AppSettings.jpegQualityRange.lowerBound,
                                  maxValue: AppSettings.jpegQualityRange.upperBound, target: nil, action: nil)
    private let valueLabel = NSTextField(labelWithString: "")
    private let qualityLabel = NSTextField(labelWithString: String(localized: "Quality:", table: "Documents"))
    private let qualityRow = NSStackView()
    private var ownPopup: NSPopUpButton?
    private var ownFormats: [UTType] = []
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - base: the accessory NSDocument already installed (its file-format popup), if any.
    ///   - formats: when non-nil, a format popup of these types is created (export panel).
    init(panel: NSSavePanel, base: NSView?, quality: Double, formats: [UTType]? = nil, selected: UTType? = nil) {
        self.panel = panel
        self.quality = min(max(quality, AppSettings.jpegQualityRange.lowerBound), AppSettings.jpegQualityRange.upperBound)
        super.init()

        view.orientation = .vertical
        view.alignment = .centerX
        view.spacing = 10
        view.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        view.detachesHiddenViews = false  // keep the panel size stable when the quality row is hidden

        if let base { view.addArrangedSubview(base) }
        if let formats {
            ownFormats = formats
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            for type in formats { popup.addItem(withTitle: type.localizedDescription ?? type.preferredFilenameExtension ?? type.identifier) }
            if let selected, let i = formats.firstIndex(of: selected) { popup.selectItem(at: i) }
            popup.target = self
            popup.action = #selector(formatChanged(_:))
            ownPopup = popup
            let row = NSStackView(views: [NSTextField(labelWithString: String(localized: "Format:", table: "Documents")), popup])
            row.spacing = 8
            view.addArrangedSubview(row)
        }

        slider.doubleValue = self.quality
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.controlSize = .regular
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        qualityRow.setViews([qualityLabel, slider, valueLabel], in: .leading)
        qualityRow.spacing = 8
        view.addArrangedSubview(qualityRow)
        updateValueLabel()

        // NSDocument's own format popup changes `allowedContentTypes` from its action; watch the
        // popup menu so the quality row follows the selected format.
        if let base, let popup = Self.findPopup(in: base) {
            observer = NotificationCenter.default.addObserver(
                forName: NSMenu.didSendActionNotification, object: popup.menu, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateQualityEnabled() }
                }
        }
        updateQualityEnabled()
    }

    /// Stops observing; call once the panel is done.
    func invalidate() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Format currently selected in the panel.
    var selectedType: UTType? {
        if let ownPopup, ownFormats.indices.contains(ownPopup.indexOfSelectedItem) { return ownFormats[ownPopup.indexOfSelectedItem] }
        return panel?.allowedContentTypes.first
    }

    /// True when `url` is what the panel returned (so the quality belongs to this save).
    func belongs(to url: URL) -> Bool {
        panel?.url?.standardizedFileURL == url.standardizedFileURL
    }

    private static func findPopup(in view: NSView) -> NSPopUpButton? {
        if let p = view as? NSPopUpButton { return p }
        for sub in view.subviews { if let p = findPopup(in: sub) { return p } }
        return nil
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let panel, ownFormats.indices.contains(sender.indexOfSelectedItem) else { return }
        let type = ownFormats[sender.indexOfSelectedItem]
        panel.allowedContentTypes = [type]
        if let ext = type.preferredFilenameExtension {
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + "." + ext
        }
        updateQualityEnabled()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        quality = sender.doubleValue
        updateValueLabel()
    }

    private func updateValueLabel() {
        valueLabel.stringValue = "\(Int((quality * 100).rounded()))%"
    }

    private func updateQualityEnabled() {
        let lossy = selectedType.map(ImageTypes.isLossy) ?? false
        slider.isEnabled = lossy
        qualityRow.isHidden = !lossy
    }
}
