import SwiftUI
import AppKit

/// Inspector options for the Text tool.
struct TextOptionsView: View {
    @Bindable var tools: ToolSettings

    private static let entries = FontFamilies.entries()

    private var familyBinding: Binding<String> {
        Binding(
            get: { FontFamilies.family(forFontName: tools.fontName) },
            set: { family in
                if let name = FontFamilies.fontName(forFamily: family) { tools.fontName = name }
            }
        )
    }

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { tools.fontSize },
            set: { tools.fontSize = min(max($0, ToolSettings.fontSizeRange.lowerBound), ToolSettings.fontSizeRange.upperBound) }
        )
    }

    var body: some View {
        let current = familyBinding.wrappedValue
        // A family outside the list (e.g. chosen in the Fonts panel) still shows under its display name.
        let entries = Self.entries.contains { $0.family == current }
            ? Self.entries
            : [FontFamilies.Entry(family: current, displayName: FontFamilies.displayName(forFamily: current))] + Self.entries
        Picker(String(localized: "Font", table: "Paint"), selection: familyBinding) {
            ForEach(entries) { Text($0.displayName).tag($0.family) }
        }
        Button(String(localized: "Fonts…", table: "Paint")) {
            NSFontManager.shared.setSelectedFont(TextTool.font(for: tools), isMultiple: false)
            NSFontManager.shared.orderFrontFontPanel(nil)
        }
        LabeledContent(String(localized: "Size", table: "Paint")) {
            HStack {
                TextField("", value: sizeBinding, format: .number.precision(.fractionLength(0)))
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: sizeBinding, in: ToolSettings.fontSizeRange, step: 1).labelsHidden()
                Text("px", tableName: "Paint").foregroundStyle(.secondary)
            }
        }
        HStack {
            Toggle(isOn: $tools.bold) { Image(systemName: "bold") }
                .help(String(localized: "Bold", table: "Paint"))
                .accessibilityLabel(String(localized: "Bold", table: "Paint"))
            Toggle(isOn: $tools.italic) { Image(systemName: "italic") }
                .help(String(localized: "Italic", table: "Paint"))
                .accessibilityLabel(String(localized: "Italic", table: "Paint"))
            Toggle(isOn: $tools.underline) { Image(systemName: "underline") }
                .help(String(localized: "Underline", table: "Paint"))
                .accessibilityLabel(String(localized: "Underline", table: "Paint"))
        }
        .toggleStyle(.button)
        Picker(String(localized: "Alignment", table: "Paint"), selection: $tools.textAlignment) {
            Image(systemName: "text.alignleft").tag(TextAlignmentSetting.left)
                .accessibilityLabel(String(localized: "Align left", table: "Paint"))
            Image(systemName: "text.aligncenter").tag(TextAlignmentSetting.center)
                .accessibilityLabel(String(localized: "Align center", table: "Paint"))
            Image(systemName: "text.alignright").tag(TextAlignmentSetting.right)
                .accessibilityLabel(String(localized: "Align right", table: "Paint"))
        }
        .pickerStyle(.segmented)
    }
}
