import AppKit

/// Connects the system colour panel (NSColorPanel) to the tool colours.
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()

    enum Slot { case primary, secondary }
    private(set) var slot: Slot = .primary

    func show(editing slot: Slot) {
        self.slot = slot
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.color = slot == .primary ? ToolSettings.shared.primaryColor : ToolSettings.shared.secondaryColor
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        switch slot {
        case .primary: ToolSettings.shared.primaryColor = sender.color
        case .secondary: ToolSettings.shared.secondaryColor = sender.color
        }
    }
}
