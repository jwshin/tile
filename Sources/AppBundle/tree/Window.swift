import AppKit
import Common

enum WindowKind { case tiled, floating, popup, minimized, hidden, nativeFullscreen }

@MainActor class Window: Hashable {
    unowned let layoutState: DisplayLayoutState
    nonisolated let windowId: UInt32
    let app: any AbstractApp
    weak var workspace: Workspace?
    var kind: WindowKind = .popup
    var resumeKind: WindowKind = .tiled
    var lastFloatingSize: CGSize?
    var isFullscreen = false
    var lastAppliedLayoutPhysicalRect: Rect?

    init(
        id: UInt32, _ app: any AbstractApp, workspace: Workspace, kind: WindowKind = .tiled,
        lastFloatingSize: CGSize? = nil
    ) {
        self.layoutState = workspace.state
        self.windowId = id
        self.app = app
        self.lastFloatingSize = lastFloatingSize
        layoutState.register(self)
        layoutState.place(self, on: workspace, kind: kind)
    }

    static func get(byId id: UInt32) -> Window? { DisplayLayoutState.shared.window(for: id) }
    nonisolated static func == (lhs: Window, rhs: Window) -> Bool { lhs === rhs }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(windowId) }
    var isFloating: Bool { kind == .floating }
    var isFocusable: Bool { kind == .tiled || kind == .floating || kind == .nativeFullscreen }
    var isRegistered: Bool { layoutState.window(for: windowId) === self }

    func nativeFocus() { die("Not implemented") }
    func closeAxWindow() { die("Not implemented") }
    func getAxSize(_ cm: CancellationMode) async throws -> CGSize? { die("Not implemented") }
    func getAxRect(_ cm: CancellationMode) async throws -> Rect? { die("Not implemented") }
    func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) { die("Not implemented") }
    func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { false }
    func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { false }
    func getCenter(_ cm: CancellationMode) async throws -> CGPoint? { try await getAxRect(cm)?.center }

    func markRecent() { workspace?.markRecent(windowId) }
    func bindAsFloatingWindow(to workspace: Workspace) { layoutState.place(self, on: workspace, kind: .floating) }
}
