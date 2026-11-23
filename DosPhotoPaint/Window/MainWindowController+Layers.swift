import AppKit

/// Layer menu actions (validation lives in `MainWindowController+Actions.isEnabled`).
extension MainWindowController {
    @objc func newLayer(_ sender: Any?) { canvas?.addLayer() }
    @objc func duplicateLayer(_ sender: Any?) { canvas?.duplicateActiveLayer() }
    @objc func deleteLayer(_ sender: Any?) { canvas?.deleteActiveLayer() }
    @objc func moveLayerUp(_ sender: Any?) { canvas?.moveActiveLayer(by: 1) }
    @objc func moveLayerDown(_ sender: Any?) { canvas?.moveActiveLayer(by: -1) }

    /// Large images are merged off the main actor (busy state blocks re-entrancy).
    @objc func mergeLayerDown(_ sender: Any?) {
        guard let canvas, !state.isLoading else { return }
        guard canvas.prefersOffloading else { canvas.mergeActiveLayerDown(); return }
        runBusy(String(localized: "Merging…", table: "Paint")) { await canvas.mergeActiveLayerDownOffloaded() }
    }

    @objc func flattenImage(_ sender: Any?) {
        guard let canvas, !state.isLoading else { return }
        guard canvas.prefersOffloading else { canvas.flatten(); return }
        runBusy(String(localized: "Flattening…", table: "Paint")) { await canvas.flattenOffloaded() }
    }

    /// Runs `work` with `state.isLoading` set; `then` receives the result on the main actor.
    func runBusy(_ message: String, then: ((Bool) -> Void)? = nil, _ work: @escaping () async -> Bool) {
        guard state.beginBusy(message) else { return }
        Task {
            let ok = await work()
            state.endBusy()
            then?(ok)
        }
    }
}
