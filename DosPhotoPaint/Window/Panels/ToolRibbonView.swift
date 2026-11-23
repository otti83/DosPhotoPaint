import SwiftUI
import AppKit

/// Horizontal tool palette shown above the canvas in Paint Mode (setting "Tool palette position:
/// Top", the default): tools, the primary/secondary colours, a quick colour palette and the
/// Smart Edit menu in one row, laid out like the ribbon of Windows Paint.
struct ToolRibbonView: View {
    let state: WindowState
    @Bindable var tools: ToolSettings
    weak var controller: MainWindowController?

    static let height: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    toolButtons
                    Divider().frame(height: 34)
                    ColorWellsView(tools: tools)
                    QuickColorPaletteView(tools: tools)
                    Divider().frame(height: 34)
                    SmartEditMenuButton(controller: controller)
                }
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
            }
            Divider()
        }
        .frame(height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolButtons: some View {
        HStack(spacing: 2) {
            ForEach(ToolKind.allCases) { kind in
                Button {
                    controller?.activateTool(kind)
                } label: {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 15))
                        .frame(width: 32, height: 30)
                        .background(tools.tool == kind ? Color.accentColor.opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Self.helpText(kind))
                .accessibilityLabel(kind.localizedName)
                .accessibilityAddTraits(tools.tool == kind ? .isSelected : [])
            }
        }
    }

    static func helpText(_ kind: ToolKind) -> String {
        if let key = kind.shortcutKey { return "\(kind.localizedName) (\(key.uppercased()))" }
        return kind.localizedName
    }
}

/// Two rows of basic colours. Click sets the primary colour, Option-click the secondary one.
struct QuickColorPaletteView: View {
    @Bindable var tools: ToolSettings

    static let rows: [[String]] = [
        ["#000000", "#7F7F7F", "#880015", "#ED1C24", "#FF7F27", "#FFF200", "#22B14C", "#00A2E8", "#3F48CC", "#A349A4"],
        ["#FFFFFF", "#C3C3C3", "#B97A57", "#FFAEC9", "#FFC90E", "#EFE4B0", "#B5E61D", "#99D9EA", "#7092BE", "#C8BFE7"],
    ]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { hex in swatch(hex) }
                }
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let color = NSColor(hexRGBA: hex) ?? .black
        return Button {
            if NSEvent.modifierFlags.contains(.option) { tools.secondaryColor = color } else { tools.primaryColor = color }
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: color))
                .frame(width: 16, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(String(localized: "Click: primary color / Option-click: secondary color", table: "Paint"))
        .accessibilityLabel(hex)
    }
}

/// "Smart Edit" pull-down (Vision / Core Image features) for the ribbon.
struct SmartEditMenuButton: View {
    weak var controller: MainWindowController?

    var body: some View {
        Menu {
            Button(String(localized: "Remove Background", table: "Paint")) { controller?.removeBackground(nil) }
            Button(String(localized: "Copy Subject to New Layer", table: "Paint")) { controller?.copySubjectToNewLayer(nil) }
            Divider()
            Button(String(localized: "Auto Enhance", table: "Paint")) { controller?.autoEnhance(nil) }
        } label: {
            Label(String(localized: "Smart Edit", table: "Paint"), systemImage: "sparkles")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(String(localized: "Smart Edit (on-device macOS image analysis)", table: "Paint"))
    }
}
