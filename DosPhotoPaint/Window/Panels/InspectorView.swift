import SwiftUI

/// Right inspector (Paint Mode): tool options and layers.
struct InspectorView: View {
    let state: WindowState
    @Bindable var tools: ToolSettings
    weak var controller: MainWindowController?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if ToolOptionsView.hasOptions(tools.tool) {
                    Section(tools.tool.localizedName) {
                        ToolOptionsView(tools: tools)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            Text("Layers", tableName: "Paint").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 8)
            LayersPanelView(state: state, controller: controller)
                .frame(minHeight: 180, idealHeight: 260)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Options for the current tool. Every numeric input is clamped to the `ToolSettings` ranges.
struct ToolOptionsView: View {
    @Bindable var tools: ToolSettings

    /// Whether `tool` has an options section. Other modules: add your tool here and in `body`.
    static func hasOptions(_ tool: ToolKind) -> Bool {
        switch tool {
        case .pen, .brush, .eraser, .fill, .eyedropper, .shape, .text, .rectangleSelect, .lassoSelect, .crop: true
        case .hand: false
        }
    }

    var body: some View {
        switch tools.tool {
        case .pen:
            numberRow(String(localized: "Width", table: "Paint"), value: $tools.penWidth, range: ToolSettings.sizeRange)
            opacityRow
        case .brush:
            Picker(String(localized: "Type", table: "Paint"), selection: $tools.brushType) {
                Text("Round", tableName: "Paint").tag(BrushType.round)
                Text("Soft", tableName: "Paint").tag(BrushType.soft)
                Text("Hard", tableName: "Paint").tag(BrushType.hard)
            }
            numberRow(String(localized: "Size", table: "Paint"), value: $tools.brushSize, range: ToolSettings.sizeRange)
            if tools.brushType == .round {
                LabeledContent(String(localized: "Hardness", table: "Paint")) {
                    HStack {
                        Slider(value: $tools.brushHardness, in: 0...1)
                        Text(String(format: "%.0f%%", tools.brushHardness * 100)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            }
            Toggle(String(localized: "Use pen pressure", table: "Paint"), isOn: $tools.usePressure)
            opacityRow
        case .eraser:
            numberRow(String(localized: "Size", table: "Paint"), value: $tools.eraserSize, range: ToolSettings.sizeRange)
            Picker(String(localized: "Background layer", table: "Paint"), selection: $tools.eraserMode) {
                Text("Erase to transparent", tableName: "Paint").tag(EraserMode.transparent)
                Text("Paint secondary color", tableName: "Paint").tag(EraserMode.backgroundColorOnBackgroundLayer)
            }
            Toggle(String(localized: "Use pen pressure", table: "Paint"), isOn: $tools.usePressure)
        case .fill:
            LabeledContent(String(localized: "Tolerance", table: "Paint")) {
                HStack {
                    Slider(value: $tools.fillTolerance, in: 0...255, step: 1)
                    clampedField($tools.fillTolerance, range: 0...255)
                }
            }
            Toggle(String(localized: "Contiguous", table: "Paint"), isOn: $tools.fillContiguous)
            opacityRow
        case .eyedropper:
            EyedropperInfoView()
        case .shape:
            shapeOptions
        case .text:
            TextOptionsView(tools: tools)
        case .rectangleSelect, .lassoSelect:
            SelectionOptionsView(tools: tools)
        case .crop:
            CropOptionsView(tools: tools)
        case .hand:
            EmptyView()
        }
    }

    // MARK: Shapes

    private static let shapeSymbols: [ShapeKind: String] = [
        .line: "line.diagonal", .rectangle: "rectangle",
        .roundedRectangle: "squareshape", .ellipse: "oval",
        .circle: "circle", .triangle: "triangle",
        .polygon: "pentagon", .arrow: "arrow.up.right",
        .curve: "scribble.variable",
    ]

    private func shapeName(_ kind: ShapeKind) -> String {
        switch kind {
        case .line: String(localized: "Line", table: "Paint")
        case .rectangle: String(localized: "Rectangle", table: "Paint")
        case .roundedRectangle: String(localized: "Rounded Rectangle", table: "Paint")
        case .ellipse: String(localized: "Ellipse", table: "Paint")
        case .circle: String(localized: "Circle", table: "Paint")
        case .triangle: String(localized: "Triangle", table: "Paint")
        case .polygon: String(localized: "Polygon", table: "Paint")
        case .arrow: String(localized: "Arrow", table: "Paint")
        case .curve: String(localized: "Curve", table: "Paint")
        }
    }

    @ViewBuilder private var shapeOptions: some View {
        let kind = tools.shapeKind
        let closed = ![.line, .arrow, .curve].contains(kind)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 28), spacing: 4), count: 5), spacing: 4) {
            ForEach(ShapeKind.allCases) { k in
                Button { tools.shapeKind = k } label: {
                    Image(systemName: Self.shapeSymbols[k] ?? "square")
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(k == kind ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(shapeName(k))
                .accessibilityLabel(shapeName(k))
                .accessibilityAddTraits(k == kind ? .isSelected : [])
            }
        }
        if closed {
            HStack {
                Toggle(String(localized: "Outline", table: "Paint"), isOn: strokeBinding)
                Spacer()
                ColorSwatchButton(color: tools.primaryColor, slot: .primary)
            }
            HStack {
                Toggle(String(localized: "Fill", table: "Paint"), isOn: fillBinding)
                Spacer()
                ColorSwatchButton(color: tools.secondaryColor, slot: .secondary)
            }
        } else {
            LabeledContent(String(localized: "Color", table: "Paint")) {
                ColorSwatchButton(color: tools.primaryColor, slot: .primary)
            }
        }
        if !closed || tools.shapeStrokeEnabled || !tools.shapeFillEnabled {
            numberRow(String(localized: "Line width", table: "Paint"), value: $tools.shapeLineWidth, range: ToolSettings.sizeRange)
        }
        if kind == .roundedRectangle {
            numberRow(String(localized: "Corner radius", table: "Paint"), value: $tools.cornerRadius, range: 0...1000)
        }
        if kind == .polygon {
            Stepper(value: $tools.polygonSides, in: ToolSettings.polygonSidesRange) {
                LabeledContent(String(localized: "Sides", table: "Paint")) {
                    Text(verbatim: "\(tools.polygonSides)").monospacedDigit()
                }
            }
        }
        opacityRow
    }

    /// At least one of outline / fill stays enabled.
    private var strokeBinding: Binding<Bool> {
        Binding(get: { tools.shapeStrokeEnabled || !tools.shapeFillEnabled }, set: { on in
            tools.shapeStrokeEnabled = on
            if !on { tools.shapeFillEnabled = true }
        })
    }

    private var fillBinding: Binding<Bool> {
        Binding(get: { tools.shapeFillEnabled }, set: { on in
            tools.shapeFillEnabled = on
            if !on { tools.shapeStrokeEnabled = true }
        })
    }

    // MARK: Rows

    private var opacityRow: some View {
        LabeledContent(String(localized: "Opacity", table: "Paint")) {
            HStack {
                Slider(value: $tools.opacity, in: 0.01...1)
                Text(String(format: "%.0f%%", tools.opacity * 100)).monospacedDigit().frame(width: 40, alignment: .trailing)
            }
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range.lowerBound...min(range.upperBound, 200))
                clampedField(value, range: range)
            }
        }
    }

    /// Text field that clamps typed values to `range` (and ignores non-finite input).
    private func clampedField(_ value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let clamped = Binding<Double>(
            get: { value.wrappedValue },
            set: { v in if v.isFinite { value.wrappedValue = min(max(v, range.lowerBound), range.upperBound) } })
        return TextField("", value: clamped, format: .number.precision(.fractionLength(0)))
            .frame(width: 48)
            .multilineTextAlignment(.trailing)
    }
}

/// Last colour picked by the eyedropper.
struct EyedropperInfoView: View {
    var body: some View {
        let state = EyedropperState.shared
        VStack(alignment: .leading, spacing: 6) {
            if let s = state.lastPicked {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: s.color)).frame(width: 36, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.4)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RGB \(s.r), \(s.g), \(s.b)", tableName: "Paint").monospacedDigit()
                        Text(verbatim: "\(s.hex)  ·  \(s.alphaPercent)%").monospacedDigit()
                    }
                    .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("No color picked yet", tableName: "Paint").foregroundStyle(.secondary)
            }
            Text("Click: primary color. Option-click: secondary color.", tableName: "Paint")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
