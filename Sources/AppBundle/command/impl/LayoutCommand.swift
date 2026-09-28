import AppKit
import Common

struct LayoutCommand: Command {
    enum Change: Sendable { case orientation, floating }
    let change: Change
    let invalidatesRestoration = true

    func run(_ io: CmdIo) async -> BinaryExitCode {
        if change == .orientation {
            focus.workspace.flipOrientation()
            return .succ
        }
        guard let window = focus.windowOrNil, let workspace = window.workspace else {
            return .fail(io.err(noWindowIsFocused))
        }
        switch window.kind {
        case .tiled:
            window.bindAsFloatingWindow(to: workspace)
            if let size = window.lastFloatingSize { window.setAxFrame(nil, size) }
        case .floating:
            let size = try? await window.getAxSize(.nonCancellable)
            guard window.isRegistered, window.workspace === workspace, window.kind == .floating else { return .fail }
            window.lastFloatingSize = size ?? window.lastFloatingSize
            window.layoutState.place(window, on: workspace, kind: .tiled)
        default: return .fail(io.err("Can't change layout of a native fullscreen, hidden, minimized, or popup window"))
        }
        return .succ
    }
}
