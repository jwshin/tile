import AppKit
import Common

open class Window: TreeNode, Hashable {
    unowned let layoutState: DisplayLayoutState
    let windowId: UInt32
    let app: any AbstractApp
    var lastFloatingSize: CGSize?
    var isFullscreen: Bool = false
    var layoutReason: LayoutReason = .standard

    @MainActor
    init(
        id: UInt32, _ app: any AbstractApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject,
        adaptiveWeight: CGFloat, index: Int
    ) {
        layoutState = parent.displayLayoutState.orDie()
        self.windowId = id
        self.app = app
        self.lastFloatingSize = lastFloatingSize
        super.init(parent: parent, adaptiveWeight: adaptiveWeight, index: index)
        layoutState.register(self)
    }

    @MainActor static func get(byId windowId: UInt32) -> Window? {
        DisplayLayoutState.shared.window(for: windowId)
    }

    @MainActor
    func closeAxWindow() { die("Not implemented") }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(windowId)
    }

    func getAxSize(_ cm: CancellationMode) async throws -> CGSize? { die("Not implemented") }
    func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { false }
    func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { false }  // todo replace with enum MacOsWindowNativeState { normal, fullscreen, invisible }
    @MainActor func nativeFocus() { die("Not implemented") }
    func getAxRect(_ cm: CancellationMode) async throws -> Rect? { die("Not implemented") }
    func getCenter(_ cm: CancellationMode) async throws -> CGPoint? { try await getAxRect(cm)?.center }

    func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) { die("Not implemented") }
}

enum LayoutReason: Equatable {
    case standard
    /// Reason for the cur temp layout is macOS native fullscreen, minimize, or hide
    case macos(prevParentKind: NonLeafTreeNodeKind)
}

extension Window {
    var isFloating: Bool {  // todo drop. It will be a source of bugs when sticky is introduced
        switch windowParentCases {
        case .floatingWindowsContainer: true
        case .macosFullscreenWindowsContainer: false
        case .macosHiddenAppsWindowsContainer: false
        case .macosMinimizedWindowsContainer: false
        case .macosPopupWindowsContainer: false
        case .tilingContainer: false
        case .unbound: false
        }
    }

    @discardableResult
    @MainActor
    func bindAsFloatingWindow(to workspace: Workspace) -> BindingData? {
        bind(to: workspace.floatingWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }

    func asMacWindow() -> MacWindow { self as! MacWindow }
}
