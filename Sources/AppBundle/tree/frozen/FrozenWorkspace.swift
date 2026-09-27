import Common

struct FrozenWorkspace: Sendable {
    let name: String
    let rootTilingNode: FrozenContainer
    let floatingWindows: [FrozenWindow]
    let macosUnconventionalWindows: [FrozenWindow]

    @MainActor init(_ workspace: Workspace) {
        name = workspace.name
        rootTilingNode = FrozenContainer(workspace.rootTilingContainer)
        floatingWindows = workspace.floatingWindows.map(FrozenWindow.init)
        macosUnconventionalWindows =
            workspace.macOsNativeHiddenAppsWindowsContainer.children.map { FrozenWindow($0 as! Window) }
            + workspace.macOsNativeFullscreenWindowsContainer.children.map { FrozenWindow($0 as! Window) }
    }
}
