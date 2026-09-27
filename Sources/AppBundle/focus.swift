import AppKit
import Common

/// This object should be only passed around but never memorized
/// Alternative name: ResolvedFocus
struct LiveFocus: TileValue, Equatable {
    let windowOrNil: Window?
    var workspace: Workspace

    @MainActor var frozen: FrozenFocus {
        return FrozenFocus(
            windowId: windowOrNil?.windowId,
            workspaceName: workspace.name,
        )
    }
}

@MainActor var focus: LiveFocus { DisplayLayoutState.shared.focus }

extension Window {
    @MainActor func focusWindow() -> Bool {
        if let focus = toLiveFocusOrNil() {
            return layoutState.setFocus(to: focus)
        } else {
            // todo We should also exit-native-hidden/unminimize[/exit-native-fullscreen?] window if we want to fix ID-B6E178F2
            //      and retry to focus the window. Otherwise, it's not possible to focus minimized/hidden windows
            return false
        }
    }

    @MainActor func toLiveFocusOrNil() -> LiveFocus? {
        visualWorkspace.map { LiveFocus(windowOrNil: self, workspace: $0) }
    }
}
extension Workspace {
    @MainActor func focusWorkspace() -> Bool { state.setFocus(to: toLiveFocus()) }

    func toLiveFocus() -> LiveFocus {
        // todo unfortunately mostRecentWindowRecursive may recursively reach empty rootTilingContainer
        //      while floating or macos unconventional windows might be presented
        if let wd = mostRecentWindowRecursive ?? anyLeafWindowRecursive {
            LiveFocus(windowOrNil: wd, workspace: self)
        } else {
            LiveFocus(windowOrNil: nil, workspace: self)  // emptyWorkspace
        }
    }
}
