import AppKit
import Common

struct FocusCommand: Command {
    let direction: CardinalDirection
    let invalidatesRestoration = false

    func run(_ io: CmdIo) async -> BinaryExitCode {
        let target = focus
        let floatingWindows = await makeFloatingWindowsSeenAsTiling(workspace: target.workspace)
        defer { restoreFloatingWindows(floatingWindows: floatingWindows, workspace: target.workspace) }
        guard let (parent, index) = target.windowOrNil?.closestParent(hasChildrenInDirection: direction) else {
            return .succ
        }
        guard
            let window = parent.children[index + direction.focusOffset]
                .findLeafWindowRecursive(snappedTo: direction.opposite)
        else { return .fail(io.err(bugPrompt())) }
        return .from(bool: window.focusWindow())
    }
}

@MainActor private func makeFloatingWindowsSeenAsTiling(workspace: Workspace) async -> [FloatingWindowData] {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    var _floatingWindows: [FloatingWindowData] = []
    for window in workspace.floatingWindows {
        // todo bug: we shouldn't access ax api here. What if the window was moved but it wasn't committed to ax yet?
        guard let center = try? await window.getCenter(.nonCancellable) else { continue }

        let tilingParent: TilingContainer
        let index: Int
        if let target = center.coerce(in: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)?
            .findWindowRecursively(in: workspace.rootTilingContainer, virtual: true, fullscreenCoversAll: false)
        {
            guard let targetCenter = try? await target.getCenter(.nonCancellable) else { continue }
            guard let _tilingParent = target.parent as? TilingContainer else { continue }
            tilingParent = _tilingParent
            index =
                center.getProjection(tilingParent.orientation)
                    >= targetCenter.getProjection(tilingParent.orientation)
                ? target.ownIndex.orDie() + 1
                : target.ownIndex.orDie()
        } else {
            index = 0
            tilingParent = workspace.rootTilingContainer
        }

        let data = window.unbindFromParent()
        let floatingWindowData = FloatingWindowData(
            window: window,
            center: center,
            tilingParent: tilingParent,
            adaptiveWeight: data.adaptiveWeight,
            index: index,
        )
        _floatingWindows.append(floatingWindowData)
    }
    let floatingWindows: [FloatingWindowData] = _floatingWindows.sortedBy {
        $0.center.getProjection($0.tilingParent.orientation)
    }.reversed()

    for floating in floatingWindows {  // Make floating windows be seen as tiling
        floating.window.bind(to: floating.tilingParent, adaptiveWeight: 1, index: floating.index)
    }
    return floatingWindows
}

@MainActor private func restoreFloatingWindows(floatingWindows: [FloatingWindowData], workspace: Workspace) {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    for floating in floatingWindows {
        floating.window.bind(
            to: workspace.floatingWindowsContainer, adaptiveWeight: floating.adaptiveWeight, index: INDEX_BIND_LAST)
    }
}

private struct FloatingWindowData {
    let window: Window
    let center: CGPoint

    let tilingParent: TilingContainer
    let adaptiveWeight: CGFloat
    let index: Int
}

extension TreeNode {
    @MainActor
    func findLeafWindowRecursive(snappedTo direction: CardinalDirection) -> Window? {
        switch nodeCases {
        case .workspace(let workspace):
            return workspace.rootTilingContainer.findLeafWindowRecursive(snappedTo: direction)
        case .window(let window):
            return window
        case .tilingContainer(let container):
            if direction.orientation == container.orientation {
                return (direction.isPositive ? container.children.last : container.children.first)?
                    .findLeafWindowRecursive(snappedTo: direction)
            } else {
                return mostRecentChild?.findLeafWindowRecursive(snappedTo: direction)
            }
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
            .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer,
            .floatingWindowsContainer:
            die("Impossible")
        }
    }
}
