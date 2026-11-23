import SwiftUI
import AppKit

/// Picker over every case of a settings enum, with localized labels.
struct SettingsEnumPicker<E: CaseIterable & Hashable>: View where E.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: E
    let label: (E) -> String

    init(_ title: String, selection: Binding<E>, label: @escaping (E) -> String) {
        self.title = title
        self._selection = selection
        self.label = label
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Array(E.allCases), id: \.self) { Text(label($0)).tag($0) }
        }
    }
}

/// Numeric text field + stepper, clamped to `range` on every edit.
struct SettingsIntField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var unit: String?

    var body: some View {
        let clamped = Binding<Int>(
            get: { min(max(value, range.lowerBound), range.upperBound) },
            set: { value = min(max($0, range.lowerBound), range.upperBound) })
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: clamped, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Stepper(title, value: clamped, in: range, step: step).labelsHidden()
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }
}

extension Binding where Value == NSColor {
    /// Bridges an `NSColor` setting to SwiftUI's `Color`.
    var swiftUIColor: Binding<Color> {
        Binding<Color>(get: { Color(nsColor: wrappedValue) },
                       set: { wrappedValue = NSColor($0).usingColorSpace(.sRGB) ?? wrappedValue })
    }
}

/// Wraps a tab's content in the standard grouped form.
struct SettingsTabForm<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}
