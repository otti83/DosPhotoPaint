import SwiftUI

/// Bottom status bar: position in folder, size, zoom, cursor, selection, edit state.
struct StatusBarView: View {
    let state: WindowState
    weak var controller: MainWindowController?

    /// The slider is hidden when the window is too narrow for it.
    @State private var showsSlider = true
    private static let sliderMinimumWidth: CGFloat = 560

    var body: some View {
        HStack(spacing: 14) {
            if state.isLoading { ProgressView().controlSize(.small) }
            if let msg = state.statusMessage {
                Text(msg).lineLimit(1).truncationMode(.tail)
            }
            if state.mode == .photo, let pos = state.sessionPosition, pos.count > 1 {
                Text(verbatim: "\(pos.index) / \(pos.count)").monospacedDigit()
                    .accessibilityLabel(Text("Image \(pos.index) of \(pos.count)", tableName: "Window"))
            }
            if let size = state.imageSize {
                Text("\(Int(size.width)) × \(Int(size.height)) px", tableName: "Window").monospacedDigit()
            }
            if state.mode == .paint, let p = state.cursorPixel {
                Label { Text(verbatim: "\(Int(p.x)), \(Int(p.y))").monospacedDigit() } icon: { Image(systemName: "cursorarrow") }
            }
            if state.mode == .paint, let sel = state.selectionSize {
                Label { Text(verbatim: "\(Int(sel.width)) × \(Int(sel.height))").monospacedDigit() } icon: { Image(systemName: "rectangle.dashed") }
            }
            Spacer(minLength: 8)
            if state.isEdited {
                Text("Edited", tableName: "Window").foregroundStyle(.secondary)
            }
            if state.isSlideshowRunning {
                Image(systemName: state.isSlideshowPaused ? "pause.fill" : "play.fill")
            }
            if state.mode == .photo, state.showsImageBrowser {
                // Over the image browser the slider sizes the thumbnails instead of zooming the image.
                let settings = AppSettings.shared
                let range = AppSettings.browserThumbnailRange
                Image(systemName: "square.grid.3x3").imageScale(.small)
                Slider(value: Binding(get: { Double(settings.photoBrowserThumbnailSize) },
                                      set: { settings.photoBrowserThumbnailSize = Int($0.rounded()) }),
                       in: Double(range.lowerBound)...Double(range.upperBound))
                    .controlSize(.mini)
                    .frame(width: 110)
                    .accessibilityLabel(Text("Thumbnail Size", tableName: "Window"))
                Image(systemName: "square.grid.2x2").imageScale(.medium)
            } else {
            if showsSlider {
                Slider(value: Binding(get: { ZoomLevels.sliderPosition(forZoom: CGFloat(state.zoom)) },
                                      set: { controller?.setZoomFromStatusBar(ZoomLevels.zoom(forSliderPosition: $0)) }),
                       in: 0...1) { editing in
                    if !editing { controller?.returnFocusToCanvas() }
                }
                .controlSize(.mini)
                .frame(width: 110)
                .accessibilityLabel(Text("Zoom", tableName: "Window"))
                .accessibilityValue(Text(String(format: "%.0f%%", state.zoom * 100)))
            }
            ZoomPercentField(zoom: state.zoom,
                             apply: { controller?.setZoomFromStatusBar($0) },
                             finish: { controller?.returnFocusToCanvas() })
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bar)
        .onGeometryChange(for: Bool.self) { $0.size.width >= Self.sliderMinimumWidth } action: { showsSlider = $0 }
    }
}

/// Zoom percentage that turns into a text field on click: Return applies (clamped), Escape cancels.
private struct ZoomPercentField: View {
    let zoom: Double
    let apply: (CGFloat) -> Void
    let finish: () -> Void

    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focused)
                    .onSubmit {
                        if let z = ZoomLevels.zoom(fromPercentText: text) { apply(z) }
                        stop()
                    }
                    .onExitCommand { stop() }
                    .onChange(of: focused) { _, isFocused in if !isFocused && editing { stop() } }
            } else {
                Text(String(format: "%.0f%%", zoom * 100)).monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        text = String(format: "%.0f", zoom * 100)
                        editing = true
                        focused = true
                    }
            }
        }
        .frame(width: 52, alignment: .trailing)
        .accessibilityLabel(Text("Zoom percentage", tableName: "Window"))
    }

    private func stop() {
        editing = false
        focused = false
        finish()
    }
}
