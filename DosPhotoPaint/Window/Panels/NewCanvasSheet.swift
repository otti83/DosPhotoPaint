import SwiftUI

/// "New Canvas" dialog: size (with presets) and background.
struct NewCanvasSheet: View {
    let clipboardSize: (width: Int, height: Int)?
    let onCreate: (NewCanvasSpec) -> Void
    let onCancel: () -> Void

    private enum Kind: Hashable { case white, secondary, transparent, custom }

    private let settingsDefault: NewCanvasSpec
    @State private var width: Int
    @State private var height: Int
    @State private var kind: Kind
    @State private var custom: Color

    init(initial: NewCanvasSpec, clipboardSize: (width: Int, height: Int)?,
         onCreate: @escaping (NewCanvasSpec) -> Void, onCancel: @escaping () -> Void) {
        self.clipboardSize = clipboardSize
        self.onCreate = onCreate
        self.onCancel = onCancel
        settingsDefault = initial
        _width = State(initialValue: initial.width)
        _height = State(initialValue: initial.height)
        switch initial.background {
        case .white: _kind = State(initialValue: .white); _custom = State(initialValue: .white)
        case .secondary: _kind = State(initialValue: .secondary); _custom = State(initialValue: .white)
        case .transparent: _kind = State(initialValue: .transparent); _custom = State(initialValue: .white)
        case .custom(let c): _kind = State(initialValue: .custom); _custom = State(initialValue: Color(nsColor: c))
        }
    }

    private var spec: NewCanvasSpec {
        let background: NewCanvasSpec.Background = switch kind {
        case .white: .white
        case .secondary: .secondary
        case .transparent: .transparent
        case .custom: .custom(NSColor(custom).usingColorSpace(.sRGB) ?? .white)
        }
        return NewCanvasSpec(width: width, height: height, background: background)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Canvas", tableName: "Paint").font(.headline)
            Form {
                LabeledContent(String(localized: "Width", table: "Paint")) { field($width) }
                LabeledContent(String(localized: "Height", table: "Paint")) { field($height) }
                LabeledContent(String(localized: "Preset", table: "Paint")) { presetMenu }
                Picker(String(localized: "Background", table: "Paint"), selection: $kind) {
                    Text("White", tableName: "Paint").tag(Kind.white)
                    Text("Secondary color", tableName: "Paint").tag(Kind.secondary)
                    Text("Transparent", tableName: "Paint").tag(Kind.transparent)
                    Text("Custom color", tableName: "Paint").tag(Kind.custom)
                }
                if kind == .custom {
                    ColorPicker(String(localized: "Color", table: "Paint"), selection: $custom, supportsOpacity: false)
                }
            }
            .formStyle(.columns)

            if !spec.isValid {
                Text("Size must be between \(AppSettings.canvasDimensionRange.lowerBound) and \(AppSettings.canvasDimensionRange.upperBound) px per side and at most \(ImageLoader.maxEditablePixels / 1_000_000) megapixels.", tableName: "Paint")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(String(localized: "Cancel", table: "Paint"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(String(localized: "Create", table: "Paint")) { onCreate(spec.clamped()) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var presetMenu: some View {
        Menu(String(localized: "Choose…", table: "Paint")) {
            Button(String(localized: "Settings default (\(settingsDefault.width) × \(settingsDefault.height))", table: "Paint")) {
                apply(settingsDefault.width, settingsDefault.height)
            }
            ForEach(NewCanvasSpec.fixedPresets, id: \.name) { preset in
                Button(preset.name) { apply(preset.width, preset.height) }
            }
            Button(String(localized: "A4 at 150 dpi (1240 × 1754)", table: "Paint")) {
                apply(NewCanvasSpec.a4At150dpi.width, NewCanvasSpec.a4At150dpi.height)
            }
            if let clipboardSize {
                Button(String(localized: "Clipboard image (\(clipboardSize.width) × \(clipboardSize.height))", table: "Paint")) {
                    apply(clipboardSize.width, clipboardSize.height)
                }
            }
        }
        .fixedSize()
    }

    private func apply(_ w: Int, _ h: Int) { width = w; height = h }

    private func field(_ value: Binding<Int>) -> some View {
        HStack {
            TextField("", value: value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("px", tableName: "Paint").foregroundStyle(.secondary)
        }
    }
}
