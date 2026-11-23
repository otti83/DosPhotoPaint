import SwiftUI

struct CanvasSizeParams {
    var width: Int
    var height: Int
    /// 3×3 anchor, 0…2 (1 = centre).
    var column: Int
    var row: Int
    /// Fill the bottom layer's new area with the secondary colour (otherwise transparent).
    var fillWithSecondary: Bool
}

/// "Canvas Size…" sheet: changes the canvas without scaling; shrinking crops.
struct CanvasSizeSheet: View {
    let original: CGSize
    let onApply: (CanvasSizeParams) -> Void
    let onCancel: () -> Void

    @State private var width: Int
    @State private var height: Int
    @State private var column = 1
    @State private var row = 1
    @State private var fillWithSecondary = true

    init(original: CGSize, onApply: @escaping (CanvasSizeParams) -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        self.onApply = onApply
        self.onCancel = onCancel
        _width = State(initialValue: Int(original.width))
        _height = State(initialValue: Int(original.height))
    }

    private var isValid: Bool { ImageResampler.isValidSize(width: width, height: height) }
    private var isUnchanged: Bool { Double(width) == original.width && Double(height) == original.height }
    private var crops: Bool { Double(width) < original.width || Double(height) < original.height }
    private var extends: Bool { Double(width) > original.width || Double(height) > original.height }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Canvas Size", tableName: "Paint").font(.headline)
            Form {
                LabeledContent(String(localized: "Width", table: "Paint")) { field($width) }
                LabeledContent(String(localized: "Height", table: "Paint")) { field($height) }
                LabeledContent(String(localized: "Anchor", table: "Paint")) { anchorGrid }
                Picker(String(localized: "New area", table: "Paint"), selection: $fillWithSecondary) {
                    Text("Secondary color", tableName: "Paint").tag(true)
                    Text("Transparent", tableName: "Paint").tag(false)
                }
                .help(String(localized: "Fill for the new area of the bottom layer. Other layers always get transparent space.", table: "Paint"))
            }
            .formStyle(.columns)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(original.width)) × \(Int(original.height)) px  →  \(width) × \(height) px", tableName: "Paint").monospacedDigit()
                if !isValid {
                    Text("Size must be between \(AppSettings.canvasDimensionRange.lowerBound) and \(AppSettings.canvasDimensionRange.upperBound) px per side and at most \(ImageLoader.maxEditablePixels / 1_000_000) megapixels.", tableName: "Paint")
                        .foregroundStyle(.red)
                } else if crops {
                    Text("Content outside the new canvas is cropped (undo restores it).", tableName: "Paint").foregroundStyle(.secondary)
                } else if extends && fillWithSecondary {
                    Text("The new area of the bottom layer is filled with the secondary color.", tableName: "Paint").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(String(localized: "Cancel", table: "Paint"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(String(localized: "Apply", table: "Paint")) {
                    onApply(CanvasSizeParams(width: width, height: height, column: column, row: row, fillWithSecondary: fillWithSecondary))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isUnchanged)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func field(_ value: Binding<Int>) -> some View {
        HStack {
            TextField("", value: value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("px", tableName: "Paint").foregroundStyle(.secondary)
        }
    }

    private var anchorGrid: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<3, id: \.self) { r in
                GridRow {
                    ForEach(0..<3, id: \.self) { c in
                        let selected = (r == row && c == column)
                        Button {
                            column = c; row = r
                        } label: {
                            Image(systemName: selected ? "circle.fill" : arrow(c, r))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? .accentColor : nil)
                        .accessibilityLabel(Text(verbatim: "\(r + 1),\(c + 1)"))
                    }
                }
            }
        }
    }

    /// Arrow pointing away from the anchor (where the canvas grows).
    private func arrow(_ c: Int, _ r: Int) -> String {
        let dx = c - column, dy = r - row
        switch (dx.signum(), dy.signum()) {
        case (-1, -1): return "arrow.up.left"
        case (0, -1): return "arrow.up"
        case (1, -1): return "arrow.up.right"
        case (-1, 0): return "arrow.left"
        case (1, 0): return "arrow.right"
        case (-1, 1): return "arrow.down.left"
        case (0, 1): return "arrow.down"
        default: return "arrow.down.right"
        }
    }
}
