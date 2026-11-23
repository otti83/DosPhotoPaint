import CoreGraphics
import Foundation

/// Editable layer attributes (undo unit for property changes).
struct LayerProperties: Equatable {
    var name: String
    var isVisible: Bool
    var opacity: Double
}

/// Layer operations. Every structural operation is one undo step and replaces buffers
/// instead of mutating them.
extension CanvasModel {

    // MARK: - Properties

    func properties(of id: UUID) -> LayerProperties? {
        layer(id: id).map { LayerProperties(name: $0.name, isVisible: $0.isVisible, opacity: $0.opacity) }
    }

    /// Sets a layer's properties. With `undoFrom`, registers one undo step restoring those values
    /// (use it once at the end of a slider drag; live updates pass nil).
    func setProperties(_ new: LayerProperties, of id: UUID, undoFrom old: LayerProperties? = nil, actionName: String? = nil) {
        guard let layer = layer(id: id) else { return }
        let visibilityOrOpacityChanged = layer.isVisible != new.isVisible || layer.opacity != new.opacity
        layer.name = new.name
        layer.isVisible = new.isVisible
        layer.opacity = min(max(new.opacity, 0), 1)
        if visibilityOrOpacityChanged { invalidateAll() }
        guard let old, old != new, let um = undoManager else { return }
        let name = actionName ?? String(localized: "Change Layer", table: "Paint")
        um.registerUndo(withTarget: self) { model in
            model.setProperties(old, of: id, undoFrom: new, actionName: name)
        }
        um.setActionName(name)
    }

    // MARK: - Add / duplicate / delete

    /// Adds a transparent layer above the active one and makes it active.
    @discardableResult
    func addLayer() -> Bool {
        guard let buffer = RasterBuffer(width: width, height: height, colorSpace: colorSpace) else { return false }
        let name = uniqueLayerName(base: String(localized: "Layer", table: "Paint"))
        let layer = Layer(name: name, buffer: buffer)
        let index = (activeLayerIndex ?? layers.count - 1) + 1
        performStructuralEdit(actionName: String(localized: "New Layer", table: "Paint")) { m in
            m.insertLayer(layer, at: index)
            m.activeLayerID = layer.id
        }
        return true
    }

    @discardableResult
    func duplicateActiveLayer() -> Bool {
        commitFloatingIfNeeded()
        guard let source = activeLayer, let index = activeLayerIndex, let buffer = source.buffer.copy() else { return false }
        let name = uniqueLayerName(base: source.name + " " + String(localized: "copy", table: "Paint"))
        let layer = Layer(name: name, buffer: buffer, isVisible: source.isVisible, opacity: source.opacity)
        performStructuralEdit(actionName: String(localized: "Duplicate Layer", table: "Paint")) { m in
            m.insertLayer(layer, at: index + 1)
            m.activeLayerID = layer.id
        }
        return true
    }

    @discardableResult
    func deleteActiveLayer() -> Bool {
        guard layers.count > 1 else { return false }
        let id = activeLayerID
        performStructuralEdit(actionName: String(localized: "Delete Layer", table: "Paint")) { m in
            m.removeLayer(id: id)
        }
        return true
    }

    func uniqueLayerName(base: String) -> String {
        let names = Set(layers.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: - Merge / flatten

    /// Merges the active layer into the one below, honouring the upper layer's opacity and
    /// visibility (a hidden layer contributes nothing). The lower layer keeps its own attributes.
    @discardableResult
    func mergeActiveLayerDown() -> Bool {
        commitFloatingIfNeeded()
        guard let index = activeLayerIndex, index > 0 else { return false }
        let upper = layers[index], lower = layers[index - 1]
        guard let merged = lower.buffer.copy() else { return false }
        CanvasRenderer.drawLayers([upper], into: merged.context, rect: bounds, preview: nil, floating: nil)
        performStructuralEdit(actionName: String(localized: "Merge Layer Down", table: "Paint")) { m in
            lower.buffer = merged
            lower.contentRevision &+= 1
            m.removeLayer(id: upper.id)
            m.activeLayerID = lower.id
        }
        return true
    }

    /// Flattens all visible layers into a single layer (hidden layers are discarded).
    @discardableResult
    func flatten() -> Bool {
        commitFloatingIfNeeded()
        guard layers.count > 1, let base = layers.first,
              let merged = RasterBuffer(width: width, height: height, colorSpace: colorSpace) else { return false }
        CanvasRenderer.drawLayers(layers, into: merged.context, rect: bounds, preview: nil, floating: nil)
        performStructuralEdit(actionName: String(localized: "Flatten Image", table: "Paint")) { m in
            base.buffer = merged
            base.isVisible = true
            base.opacity = 1
            base.contentRevision &+= 1
            for layer in m.layers.dropFirst() { m.removeLayer(id: layer.id) }
            m.activeLayerID = base.id
        }
        return true
    }

    // MARK: - Order

    @discardableResult
    func moveActiveLayer(by delta: Int) -> Bool {
        guard let index = activeLayerIndex else { return false }
        let target = index + delta
        guard layers.indices.contains(target) else { return false }
        let id = activeLayerID
        let name = delta > 0 ? String(localized: "Move Layer Up", table: "Paint") : String(localized: "Move Layer Down", table: "Paint")
        performStructuralEdit(actionName: name) { m in m.moveLayer(id: id, to: target) }
        return true
    }

    /// Applies a full order (bottom → top) after a drag in the panel.
    func reorderLayers(bottomToTop ids: [UUID]) {
        guard Set(ids) == Set(layers.map(\.id)), ids != layers.map(\.id) else { return }
        performStructuralEdit(actionName: String(localized: "Reorder Layers", table: "Paint")) { m in
            for (i, id) in ids.enumerated() { m.moveLayer(id: id, to: i) }
        }
    }
}
