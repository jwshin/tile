import Common

extension Workspace {
    @MainActor var rootTilingContainer: TilingContainer {
        let containers = children.filterIsInstance(of: TilingContainer.self)
        switch containers.count {
        case 0:
            let orientation: Orientation = workspaceMonitor.width >= workspaceMonitor.height ? .h : .v
            return TilingContainer(parent: self, adaptiveWeight: 1, orientation, index: INDEX_BIND_LAST)
        case 1:
            return containers.singleOrNil().orDie()
        default:
            die("Workspace must contain zero or one tiling container as its child")
        }
    }

    @MainActor
    var floatingWindows: [Window] {
        floatingWindowsContainer.children.filterIsInstance(of: Window.self)
    }

    @MainActor
    var floatingWindowsContainer: FloatingWindowsContainer {
        let containers = children.filterIsInstance(of: FloatingWindowsContainer.self)
        return switch containers.count {
        case 0: FloatingWindowsContainer(parent: self)
        case 1: containers.singleOrNil().orDie()
        default: dieT("Workspace must contain zero or one FloatingWindowsContainer")
        }
    }

    @MainActor var macOsNativeFullscreenWindowsContainer: MacosFullscreenWindowsContainer {
        let containers = children.filterIsInstance(of: MacosFullscreenWindowsContainer.self)
        return switch containers.count {
        case 0: MacosFullscreenWindowsContainer(parent: self)
        case 1: containers.singleOrNil().orDie()
        default: dieT("Workspace must contain zero or one MacosFullscreenWindowsContainer")
        }
    }

    @MainActor var macOsNativeHiddenAppsWindowsContainer: MacosHiddenAppsWindowsContainer {
        let containers = children.filterIsInstance(of: MacosHiddenAppsWindowsContainer.self)
        return switch containers.count {
        case 0: MacosHiddenAppsWindowsContainer(parent: self)
        case 1: containers.singleOrNil().orDie()
        default: dieT("Workspace must contain zero or one MacosHiddenAppsWindowsContainer")
        }
    }
}
