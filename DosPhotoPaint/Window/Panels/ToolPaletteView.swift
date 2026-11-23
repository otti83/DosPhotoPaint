import SwiftUI

/// Left tool palette (Paint Mode). Tool buttons flow into as many columns as fit (1–2).
struct ToolPaletteView: View {
    let state: WindowState
    @Bindable var tools: ToolSettings
    weak var controller: MainWindowController?

    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 44), spacing: 4)]

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 4) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(ToolKind.allCases) { kind in
                        Button {
                            controller?.activateTool(kind)
                        } label: {
                            Image(systemName: kind.symbolName)
                                .font(.system(size: 15))
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(tools.tool == kind ? Color.accentColor.opacity(0.25) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(helpText(kind))
                        .accessibilityLabel(kind.localizedName)
                        .accessibilityHint(kind.shortcutKey.map { String(localized: "Shortcut \($0.uppercased())", table: "Paint") } ?? "")
                        .accessibilityAddTraits(tools.tool == kind ? .isSelected : [])
                    }
                }
                Divider().padding(.vertical, 4)
                ColorWellsView(tools: tools)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
        }
        // Explicit semantic backing: the palette is a plain (non-sidebar) split item, so it must not
        // depend on whatever is behind it for contrast in Light and Dark.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func helpText(_ kind: ToolKind) -> String {
        if let key = kind.shortcutKey { return "\(kind.localizedName) (\(key.uppercased()))" }
        return kind.localizedName
    }
}

/// Primary / secondary colour swatches (click opens the system colour panel).
struct ColorWellsView: View {
    @Bindable var tools: ToolSettings

    var body: some View {
        ZStack(alignment: .topLeading) {
            ColorSwatchButton(color: tools.secondaryColor, slot: .secondary).offset(x: 12, y: 12)
            ColorSwatchButton(color: tools.primaryColor, slot: .primary)
        }
        .frame(width: 40, height: 40)
        .overlay(alignment: .bottomLeading) {
            Button { tools.swapColors() } label: { Image(systemName: "arrow.left.arrow.right").font(.system(size: 9)) }
                .buttonStyle(.plain)
                .help(String(localized: "Swap Colors (X)", table: "Paint"))
                .accessibilityLabel(String(localized: "Swap Colors", table: "Paint"))
                .offset(x: -2, y: 4)
        }
    }
}

/// A colour swatch that opens the system colour panel for `slot`.
struct ColorSwatchButton: View {
    let color: NSColor
    let slot: ColorPanelBridge.Slot

    private var title: String {
        slot == .primary ? String(localized: "Primary Color", table: "Paint") : String(localized: "Secondary Color", table: "Paint")
    }

    var body: some View {
        Button {
            ColorPanelBridge.shared.show(editing: slot)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: color))
                .frame(width: 26, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(color.hexRGB)
    }
}
