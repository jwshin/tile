import AppKit

@testable import AppBundle

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?
    var deferFrameWrites = false
    private var pendingFrame: Rect?
    var beforeNextSizeRead: (@MainActor () async throws -> Void)?
    var isMacosFullscreenForTest = false
    var isMacosMinimizedForTest = false

    private init(_ id: UInt32, _ workspace: Workspace, _ kind: WindowKind, _ rect: Rect?) {
        _rect = rect
        super.init(id: id, TestApp.shared, workspace: workspace, kind: kind)
    }

    @discardableResult
    static func new(id: UInt32, workspace: Workspace, kind: WindowKind = .tiled, rect: Rect? = nil) -> TestWindow {
        let window = TestWindow(id, workspace, kind, rect)
        TestApp.shared._windows.append(window)
        return window
    }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    @MainActor
    override func nativeFocus() {
        TestApp.shared.focusedWindow = self
    }

    override func closeAxWindow() {
        layoutState.removeWindow(self, remember: false)
    }

    @MainActor override func getAxRect(_ cm: CancellationMode) async throws -> Rect? {  // todo change to not Optional
        _rect
    }

    @MainActor override func getAxSize(_ cm: CancellationMode) async throws -> CGSize? {
        let beforeRead = beforeNextSizeRead
        beforeNextSizeRead = nil
        try await beforeRead?()
        return _rect.map { CGSize(width: $0.width, height: $0.height) }
    }

    override func setAxFrame(_ point: CGPoint?, _ size: CGSize?) {
        let old = _rect ?? Rect(topLeftX: 0, topLeftY: 0, width: 400, height: 300)
        let frame = Rect(
            topLeftX: point?.x ?? old.minX, topLeftY: point?.y ?? old.minY,
            width: size?.width ?? old.width, height: size?.height ?? old.height)
        if deferFrameWrites { pendingFrame = frame } else { _rect = frame }
    }

    override func cancelPendingFrame() { pendingFrame = nil }

    func flushPendingFrame() {
        if let pendingFrame { _rect = pendingFrame }
        pendingFrame = nil
    }

    override func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { isMacosMinimizedForTest }

    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { isMacosFullscreenForTest }
}
