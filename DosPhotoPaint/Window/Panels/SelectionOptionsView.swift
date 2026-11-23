import SwiftUI

/// Inspector options of the selection tools.
struct SelectionOptionsView: View {
    @Bindable var tools: ToolSettings

    var body: some View {
        Toggle(String(localized: "Transparent selection", table: "Paint"), isOn: $tools.transparentSelection)
            .help(String(localized: "Pixels matching the secondary color become transparent when a selection is moved or pasted.", table: "Paint"))
        Text("Drag inside a selection to move it. Return applies, Escape cancels.", tableName: "Paint")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Inspector options of the crop tool.
struct CropOptionsView: View {
    @Bindable var tools: ToolSettings
    private let status = CropStatus.shared

    var body: some View {
        Picker(String(localized: "Aspect Ratio", table: "Paint"), selection: $tools.cropAspect) {
            ForEach(CropAspect.allCases) { aspect in
                Text(aspect.label).tag(aspect)
            }
        }
        HStack {
            Button(String(localized: "Cancel", table: "Paint")) {
                NSApp.sendAction(#selector(MainWindowController.cancelCrop(_:)), to: nil, from: nil)
            }
            Button(String(localized: "Apply Crop", table: "Paint")) {
                NSApp.sendAction(#selector(MainWindowController.applyCrop(_:)), to: nil, from: nil)
            }
            .keyboardShortcut(.defaultAction)
        }
        .disabled(!status.hasPendingCrop)
        Text("Drag on the image to choose the area. Return applies, Escape cancels.", tableName: "Paint")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private extension CropAspect {
    var label: String {
        switch self {
        case .free: String(localized: "Free", table: "Paint")
        case .original: String(localized: "Original", table: "Paint")
        case .square: String(localized: "1:1", table: "Paint")
        case .fourThree: String(localized: "4:3", table: "Paint")
        case .sixteenNine: String(localized: "16:9", table: "Paint")
        }
    }
}
