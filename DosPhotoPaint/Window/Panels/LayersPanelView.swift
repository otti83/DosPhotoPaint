import SwiftUI

/// Layer list shown in the inspector: top layer first, thumbnails, visibility, rename,
/// opacity of the active layer, add/duplicate/merge/delete and drag-to-reorder.
struct LayersPanelView: View {
    let state: WindowState
    weak var controller: MainWindowController?

    /// The window's canvas. Reading `imageSize` makes the panel refresh when a canvas attaches.
    private var model: CanvasModel? {
        _ = state.imageSize
        _ = state.canvasGeneration
        return controller?.canvas
    }

    var body: some View {
        if let model {
            LayerListView(model: model, controller: controller)
        } else {
            Text("No layers", tableName: "Paint").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LayerListView: View {
    let model: CanvasModel
    weak var controller: MainWindowController?

    @State private var renamingID: UUID?
    @State private var dragStart: LayerProperties?

    /// Display order: top → bottom.
    private var displayLayers: [Layer] { model.layers.reversed() }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(displayLayers) { layer in
                    LayerRow(layer: layer, model: model, isActive: layer.id == model.activeLayerID,
                             renamingID: $renamingID)
                        .contentShape(Rectangle())
                        .onTapGesture { model.activeLayerID = layer.id }
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                        .listRowBackground(layer.id == model.activeLayerID ? Color.accentColor.opacity(0.22) : Color.clear)
                }
                .onMove { source, destination in
                    var order = displayLayers.map(\.id)
                    order.move(fromOffsets: source, toOffset: destination)
                    model.reorderLayers(bottomToTop: order.reversed())
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 40)

            Divider()
            opacityRow
            buttonBar
        }
    }

    @ViewBuilder private var opacityRow: some View {
        if let active = model.activeLayer {
            HStack {
                Text("Opacity", tableName: "Paint").font(.caption)
                Slider(value: Binding(
                    get: { active.opacity },
                    set: { v in
                        guard var p = model.properties(of: active.id) else { return }
                        p.opacity = v
                        model.setProperties(p, of: active.id)
                    }), in: 0...1) { editing in
                    if editing {
                        dragStart = model.properties(of: active.id)
                    } else if let start = dragStart, let now = model.properties(of: active.id) {
                        // One undo step for the whole drag.
                        model.setProperties(now, of: active.id, undoFrom: start, actionName: String(localized: "Layer Opacity", table: "Paint"))
                        dragStart = nil
                    }
                }
                Text(String(format: "%.0f%%", active.opacity * 100)).monospacedDigit().font(.caption)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 8).padding(.top, 6)
        }
    }

    private var buttonBar: some View {
        HStack(spacing: 4) {
            button("plus", String(localized: "New Layer", table: "Paint")) { controller?.newLayer(nil) }
            button("plus.square.on.square", String(localized: "Duplicate Layer", table: "Paint")) { controller?.duplicateLayer(nil) }
            button("arrow.down.to.line", String(localized: "Merge Layer Down", table: "Paint"), enabled: (model.activeLayerIndex ?? 0) > 0) { controller?.mergeLayerDown(nil) }
            Spacer()
            button("trash", String(localized: "Delete Layer", table: "Paint"), enabled: model.layers.count > 1) { controller?.deleteLayer(nil) }
        }
        .padding(6)
    }

    private func button(_ symbol: String, _ help: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(Text(help))
            .disabled(!enabled)
    }
}

private struct LayerRow: View {
    let layer: Layer
    let model: CanvasModel
    let isActive: Bool
    @Binding var renamingID: UUID?
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard var p = model.properties(of: layer.id) else { return }
                p.isVisible.toggle()
                model.setProperties(p, of: layer.id, undoFrom: model.properties(of: layer.id),
                                    actionName: p.isVisible ? String(localized: "Show Layer", table: "Paint") : String(localized: "Hide Layer", table: "Paint"))
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .frame(width: 20)
                    .foregroundStyle(layer.isVisible ? Color.primary : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(layer.isVisible ? String(localized: "Hide Layer", table: "Paint") : String(localized: "Show Layer", table: "Paint"))

            LayerThumbnail(layer: layer, size: model.size)

            if renamingID == layer.id {
                TextField("", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { renamingID = nil }
                    .onAppear { draftName = layer.name; nameFocused = true }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
            } else {
                Text(layer.name).lineLimit(1).truncationMode(.tail)
                    .opacity(layer.isVisible ? 1 : 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.activeLayerID = layer.id; renamingID = layer.id }
            }
        }
    }

    private func commitRename() {
        guard renamingID == layer.id else { return }
        renamingID = nil
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != layer.name, var p = model.properties(of: layer.id) else { return }
        let old = p
        p.name = name
        model.setProperties(p, of: layer.id, undoFrom: old, actionName: String(localized: "Rename Layer", table: "Paint"))
    }
}

/// Small preview of a layer, regenerated (debounced) when `contentRevision` changes.
private struct LayerThumbnail: View {
    let layer: Layer
    let size: CGSize
    @State private var image: CGImage?

    private static let edge: CGFloat = 32

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.15))
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            }
        }
        .frame(width: Self.edge, height: Self.edge)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
        .task(id: layer.contentRevision) {
            // Debounce: painting bumps the revision after every stroke.
            if image != nil { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            image = Self.makeThumbnail(layer.buffer)
        }
    }

    /// Downscales the buffer (zero-copy source view) into a retina-sized bitmap.
    private static func makeThumbnail(_ buffer: RasterBuffer) -> CGImage? {
        let scale = Self.edge * 2 / CGFloat(max(buffer.width, buffer.height))
        let w = max(1, Int((CGFloat(buffer.width) * scale).rounded())), h = max(1, Int((CGFloat(buffer.height) * scale).rounded()))
        guard let ctx = ImageTransforms.makeRGBAContext(width: w, height: h, colorSpace: buffer.colorSpace) else { return nil }
        ctx.interpolationQuality = .medium
        _ = buffer.withImage { ctx.draw($0, in: CGRect(x: 0, y: 0, width: w, height: h)) }
        return ctx.makeImage()
    }
}
