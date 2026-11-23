import Observation

private struct WeakRef<T: AnyObject>: @unchecked Sendable { weak var value: T? }
private struct UncheckedBox<T>: @unchecked Sendable { let value: T }

/// Calls `apply` now and again every time an observable property read inside it changes.
/// Stops when `owner` is deallocated. Main-actor only.
func observeContinuously<Owner: AnyObject>(_ owner: Owner, _ apply: @escaping (Owner) -> Void) {
    let ref = WeakRef(value: owner)
    let box = UncheckedBox(value: apply)
    withObservationTracking {
        apply(owner)
    } onChange: {
        Task { @MainActor in
            guard let owner = ref.value else { return }
            observeContinuously(owner, box.value)
        }
    }
}
