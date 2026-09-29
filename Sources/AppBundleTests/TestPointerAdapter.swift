import AppKit

@testable import AppBundle

@MainActor final class TestPointerAdapter: PointerAdapter {
    var isButtonDown = true
    private(set) var preview: MouseTiling.Preview?
    func showPreview(_ preview: MouseTiling.Preview?) { self.preview = preview }
}

/// Supplies native-style frame samples without reimplementing gesture policy.
@MainActor final class TestPointerDriver {
    private let state: DisplayLayoutState
    private var sample: (Window, Rect)?

    init(state: DisplayLayoutState) { self.state = state }
    var preview: MouseTiling.Preview? { state.pointerPreview }

    func observe(_ window: Window, frame: Rect) {
        sample = (window, frame)
        if let workspace = window.workspace {
            state.updatePointer(window, frame: frame, at: frame.center, on: workspace)
        }
    }
    func drag(at point: CGPoint, on destination: Workspace) {
        guard let (window, frame) = sample else { return }
        state.updatePointer(window, frame: frame, at: point, on: destination)
    }
    func finish(at point: CGPoint, on destination: Workspace) {
        state.finishPointer(at: point, on: destination)
    }
    func cancel() { state.cancelPointer() }
}
