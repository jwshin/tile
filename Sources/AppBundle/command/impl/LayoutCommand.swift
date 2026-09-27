import Common

struct LayoutCommand: Command {
    enum Change: Sendable { case orientation, floating }
    let change: Change
    let invalidatesRestoration = true

    func run(_ io: CmdIo) async -> BinaryExitCode {
        let target = focus
        guard let window = target.windowOrNil else {
            if change == .orientation {
                let root = target.workspace.rootTilingContainer
                root.changeOrientation(root.orientation.opposite)
                return .succ
            }
            return .fail(io.err(noWindowIsFocused))
        }
        switch window.windowParentCases {
        case .tilingContainer(let parent):
            if change == .orientation {
                parent.changeOrientation(parent.orientation.opposite)
            } else {
                window.bindAsFloatingWindow(to: target.workspace)
                if let size = window.lastFloatingSize { window.setAxFrame(nil, size) }
            }
            return .succ
        case .floatingWindowsContainer:
            guard change == .floating else { return .fail(io.err("The window is non-tiling")) }
            window.lastFloatingSize = (try? await window.getAxSize(.nonCancellable)) ?? window.lastFloatingSize
            do {
                try await window.relayoutWindow(on: target.workspace, .nonCancellable, forceTile: true)
                return .succ
            } catch { return .fail(io.err(bugPrompt())) }
        case .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer, .macosMinimizedWindowsContainer:
            return .fail(io.err("Can't change layout for macOS fullscreen, hidden, or minimized windows"))
        case .unbound, .macosPopupWindowsContainer:
            return .fail(io.err(bugPrompt()))
        }
    }
}
