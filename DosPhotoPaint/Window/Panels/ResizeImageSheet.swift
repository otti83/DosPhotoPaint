import SwiftUI

struct ResizeParams {
    var width: Int
    var height: Int
    var interpolation: ResampleInterpolation
}

/// "Resize Image…" sheet: scales the whole image (all layers) to a new pixel size.
struct ResizeImageSheet: View {
    let original: CGSize
    let onApply: (ResizeParams) -> Void
    let onCancel: () -> Void

    private enum Unit: Hashable { case pixels, percent }

    @State private var unit: Unit = .pixels
    @State private var width: Int
    @State private var height: Int
    @State private var lockAspect = true
    @State private var interpolation: ResampleInterpolation = .high

    init(original: CGSize, onApply: @escaping (ResizeParams) -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        self.onApply = onApply
        self.onCancel = onCancel
        _width = State(initialValue: Int(original.width))
        _height = State(initialValue: Int(original.height))
    }

    private var ow: Double { max(original.width, 1) }
    private var oh: Double { max(original.height, 1) }

    private var widthValue: Binding<Double> {
        Binding(
            get: { unit == .pixels ? Double(width) : Double(width) / ow * 100 },
            set: { v in
                width = pixels(from: v, of: ow)
                if lockAspect { height = clamp(Int((Double(width) * oh / ow).rounded())) }
            })
    }

    private var heightValue: Binding<Double> {
        Binding(
            get: { unit == .pixels ? Double(height) : Double(height) / oh * 100 },
            set: { v in
                height = pixels(from: v, of: oh)
                if lockAspect { width = clamp(Int((Double(height) * ow / oh).rounded())) }
            })
    }

    private func pixels(from value: Double, of original: Double) -> Int {
        guard value.isFinite else { return 1 }
        let px = unit == .pixels ? value : original * value / 100
        return clamp(Int(min(max(px, 1), 1_000_000).rounded()))
    }

    private func clamp(_ v: Int) -> Int { max(v, 1) }

    private var isValid: Bool { ImageResampler.isValidSize(width: width, height: height) }
    private var isEnlarging: Bool { Double(width) > ow || Double(height) > oh }
    private var isUnchanged: Bool { Double(width) == ow && Double(height) == oh }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resize Image", tableName: "Paint").font(.headline)
            Form {
                Picker(String(localized: "Units", table: "Paint"), selection: $unit) {
                    Text("Pixels", tableName: "Paint").tag(Unit.pixels)
                    Text("Percent", tableName: "Paint").tag(Unit.percent)
                }
                .pickerStyle(.segmented)
                LabeledContent(String(localized: "Width", table: "Paint")) { field(widthValue) }
                LabeledContent(String(localized: "Height", table: "Paint")) { field(heightValue) }
                Toggle(String(localized: "Lock aspect ratio", table: "Paint"), isOn: $lockAspect)
                Picker(String(localized: "Interpolation", table: "Paint"), selection: $interpolation) {
                    Text("High Quality (photos)", tableName: "Paint").tag(ResampleInterpolation.high)
                    Text("Nearest Neighbor (pixel art)", tableName: "Paint").tag(ResampleInterpolation.nearest)
                }
            }
            .formStyle(.columns)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(original.width)) × \(Int(original.height)) px  →  \(width) × \(height) px", tableName: "Paint")
                    .monospacedDigit()
                if !isValid {
                    Text("Size must be between \(AppSettings.canvasDimensionRange.lowerBound) and \(AppSettings.canvasDimensionRange.upperBound) px per side and at most \(ImageLoader.maxEditablePixels / 1_000_000) megapixels.", tableName: "Paint")
                        .foregroundStyle(.red)
                } else if isEnlarging {
                    Text("Enlarging cannot add detail; the result may look soft or blocky.", tableName: "Paint")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(String(localized: "Cancel", table: "Paint"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(String(localized: "Resize", table: "Paint")) {
                    onApply(ResizeParams(width: width, height: height, interpolation: interpolation))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isUnchanged)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func field(_ value: Binding<Double>) -> some View {
        HStack {
            TextField("", value: value, format: .number.precision(.fractionLength(0...1)))
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit == .pixels ? LocalizedStringKey("px") : LocalizedStringKey("%"), tableName: "Paint").foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
        }
    }
}
