import CoreGraphics
import Foundation
import Observation

/// One raster layer. Property changes are observable (for the layers panel).
///
/// Rule: **structural edits never mutate `buffer` in place** — they assign a new buffer.
/// This lets undo snapshots keep the old buffer by reference instead of copying pixels.
/// Only region edits (painting) mutate the buffer, and those are covered by region undo.
@Observable
final class Layer: Identifiable {
    let id: UUID
    var name: String
    var isVisible: Bool
    /// 0…1
    var opacity: Double
    @ObservationIgnored var buffer: RasterBuffer
    /// Bumped whenever pixels change (drives thumbnail refresh).
    var contentRevision: Int = 0

    init(id: UUID = UUID(), name: String, buffer: RasterBuffer, isVisible: Bool = true, opacity: Double = 1) {
        self.id = id
        self.name = name
        self.buffer = buffer
        self.isVisible = isVisible
        self.opacity = min(max(opacity, 0), 1)
    }
}

/// Immutable record of a layer's state for snapshot undo. Holds the buffer by reference.
struct LayerState {
    let id: UUID
    let name: String
    let isVisible: Bool
    let opacity: Double
    let buffer: RasterBuffer
}

/// Whole-canvas structural state for snapshot undo.
struct CanvasSnapshot {
    let width: Int
    let height: Int
    let layers: [LayerState]
    let activeLayerID: UUID
    let selection: CanvasSelection?
}
