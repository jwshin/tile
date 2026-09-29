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
    var minimumSize = BinaryLayout.baseline
    var isResizable = true
    private var constraintCandidate: CGSize?
    var lastFocusSequence: UInt64 = 0
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
    var isFocusable: Bool { kind == .tiled || kind == .floating }
    var isRegistered: Bool { layoutState.window(for: windowId) === self }

    func nativeFocus() { die("Not implemented") }
    func closeAxWindow() { die("Not implemented") }
    func getAxSize(_ cm: CancellationMode) async throws -> CGSize? { die("Not implemented") }
    func getAxRect(_ cm: CancellationMode) async throws -> Rect? { die("Not implemented") }
    func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) { die("Not implemented") }
    func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { false }
    func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { false }
    func getCenter(_ cm: CancellationMode) async throws -> CGPoint? { try await getAxRect(cm)?.center }

    /// Keep the actual applied size as the next gesture's baseline, including app rounding/cell snapping.
    @discardableResult func observeAppliedSize(requested: CGSize, actual: CGSize) -> Bool {
        let learnedMinimum = observeSizeConstraint(requested: requested, actual: actual)
        if lastAppliedLayoutPhysicalRect?.size == requested, layoutState.manipulatedWindow !== self {
            lastAppliedLayoutPhysicalRect?.width = actual.width
            lastAppliedLayoutPhysicalRect?.height = actual.height
        }
        return learnedMinimum
    }

    /// Ignore small discrepancies (for example terminal cell snapping); require two matching
    /// successful native writes before learning a substantially larger application limit.
    @discardableResult func observeSizeConstraint(requested: CGSize, actual: CGSize) -> Bool {
        guard isRegistered, kind == .tiled, !isFullscreen,
            layoutState.manipulatedWindow !== self,
            lastAppliedLayoutPhysicalRect?.size == requested
        else {
            constraintCandidate = nil
            return false
        }
        let candidate = CGSize(
            width: actual.width > requested.width + 32 ? max(minimumSize.width, actual.width) : minimumSize.width,
            height: actual.height > requested.height + 32 ? max(minimumSize.height, actual.height) : minimumSize.height)
        guard candidate != minimumSize else {
            constraintCandidate = nil
            return false
        }
        guard constraintCandidate == candidate else {
            constraintCandidate = candidate
            return false
        }
        layoutState.cancelPointer()
        minimumSize = candidate
        constraintCandidate = nil
        return true
    }

    func markRecent() { workspace?.markRecent(windowId) }
    func bindAsFloatingWindow(to workspace: Workspace) { layoutState.place(self, on: workspace, kind: .floating) }
}
