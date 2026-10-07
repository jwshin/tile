import AppKit
import Common
import PrivateApi

@MainActor
func waitForAccessibilityPermission_nonCancellable() async {
    let options = [axTrustedCheckOptionPrompt: true]
    while true {
        let status =
            TrayMenuModel.shared.axPermissionStatus == .waitingWithPrompt
            ? AXIsProcessTrustedWithOptions(options as CFDictionary)
            : AXIsProcessTrusted()
        if status {
            TrayMenuModel.shared.axPermissionStatus = .granted
            break
        }
        if TrayMenuModel.shared.axPermissionStatus == .waitingWithPrompt {
            resetAccessibility()  // Because macOS doesn't reset it for us when the app signature changes...
        }
        TrayMenuModel.shared.axPermissionStatus = .waiting
        try? await Task.sleep(for: .seconds(1))
    }
}

private func resetAccessibility() {
    _ = try? Process.run(URL(filePath: "/usr/bin/tccutil"), arguments: ["reset", "Accessibility", appId])
}

protocol ReadableAttr: Sendable {
    associatedtype T
    var getter: @Sendable (AnyObject) -> T? { get }
    var key: String { get }
}

protocol WritableAttr: ReadableAttr, Sendable {
    var setter: @Sendable (T) -> CFTypeRef? { get }
}

enum Ax {
    struct ReadableAttrImpl<T>: ReadableAttr {
        var key: String
        var getter: @Sendable (AnyObject) -> T?
    }

    struct WritableAttrImpl<T>: WritableAttr {
        var key: String
        var getter: @Sendable (AnyObject) -> T?
        var setter: @Sendable (T) -> CFTypeRef?
    }

    static let titleAttr = ReadableAttrImpl<String>(
        key: kAXTitleAttribute,
        getter: { $0 as? String },
    )
    static let subroleAttr = ReadableAttrImpl<String>(
        key: kAXSubroleAttribute,
        getter: { $0 as? String },
    )
    static let identifierAttr = ReadableAttrImpl<String>(
        key: kAXIdentifierAttribute,
        getter: { $0 as? String },
    )
    static let enabledAttr = ReadableAttrImpl<Bool>(
        key: kAXEnabledAttribute,
        getter: { $0 as? Bool },
    )
    static let enhancedUserInterfaceAttr = WritableAttrImpl<Bool>(
        key: "AXEnhancedUserInterface",
        getter: { $0 as? Bool },
        setter: { $0 as CFTypeRef },
    )
    static let minimizedAttr = ReadableAttrImpl<Bool>(
        key: kAXMinimizedAttribute,
        getter: { $0 as? Bool },
    )
    static let isFullscreenAttr = ReadableAttrImpl<Bool>(
        key: "AXFullScreen",
        getter: { $0 as? Bool },
    )
    static let isFocused = ReadableAttrImpl<Bool>(
        key: kAXFocusedAttribute,
        getter: { $0 as? Bool },
    )
    static let isMainAttr = WritableAttrImpl<Bool>(
        key: kAXMainAttribute,
        getter: { $0 as? Bool },
        setter: { $0 as CFTypeRef },
    )
    static let sizeAttr = WritableAttrImpl<CGSize>(
        key: kAXSizeAttribute,
        getter: {
            var raw: CGSize = .zero
            check(unsafe AXValueGetValue($0 as! AXValue, .cgSize, &raw))
            return raw
        },
        setter: {
            var size = $0
            return unsafe AXValueCreate(.cgSize, &size) as CFTypeRef
        },
    )
    static let topLeftCornerAttr = WritableAttrImpl<CGPoint>(
        key: kAXPositionAttribute,
        getter: {
            var raw: CGPoint = .zero
            check(unsafe AXValueGetValue($0 as! AXValue, .cgPoint, &raw))
            return raw
        },
        setter: {
            var size = $0
            return unsafe AXValueCreate(.cgPoint, &size) as CFTypeRef
        },
    )
    /// Returns windows visible on all monitors
    /// If some windows are located on not active macOS Spaces then they won't be returned
    static let windowsAttr = ReadableAttrImpl<[WindowIdAndAxUiElement]>(
        key: kAXWindowsAttribute,
        getter: { ($0 as? NSArray)?.compactMap(windowOrNil).map { ($0.windowId, $0.ax.cast) } ?? [] },
    )
    static let focusedWindowAttr = ReadableAttrImpl<WindowIdAndAxUiElementMock>(
        key: kAXFocusedWindowAttribute,
        getter: windowOrNil,
    )
    static let closeButtonAttr = ReadableAttrImpl<any AxUiElementMock>(
        key: kAXCloseButtonAttribute,
        getter: castToAxUiElementMock,
    )
    // Note! fullscreen is not the same as "zoom" (green plus)
    static let fullscreenButtonAttr = ReadableAttrImpl<any AxUiElementMock>(
        key: kAXFullScreenButtonAttribute,
        getter: castToAxUiElementMock,
    )
    // green plus
    static let zoomButtonAttr = ReadableAttrImpl<any AxUiElementMock>(
        key: kAXZoomButtonAttribute,
        getter: castToAxUiElementMock,
    )
    static let minimizeButtonAttr = ReadableAttrImpl<any AxUiElementMock>(
        key: kAXMinimizeButtonAttribute,
        getter: castToAxUiElementMock,
    )
}

let kAXTileSynthetic = "tile.synthetic"

private func castToAxUiElementMock(_ a: AnyObject) -> AxUiElementMock {
    if isUnitTest {
        if let str = a as? String, let commaIndex = str.firstIndex(of: ",") {
            let windowId = UInt32.init(String(str.prefix(upTo: commaIndex)).removePrefix("AXUIElement(AxWindowId="))
            if let windowId {
                return castToAxUiElementMock(
                    [
                        "tile.axWindowId": Json.int(windowId),
                        kAXTileSynthetic: Json.bool(true),
                    ] as AnyObject)
            }
        }
        if let dict = a as? [String: Json] {  // Convert from _SwiftDeferredNSDictionary<String, Json>
            return dict as? AxUiElementMock ?? dieT("Cannot cast \(type(of: a)) to AxUiElementMock")
        }
        die("Can't convert \(a) to AxUiElementMock")
    }
    return a as! AXUIElement
}

typealias WindowIdAndAxUiElement = (windowId: UInt32, ax: AXUIElement)
typealias WindowIdAndAxUiElementMock = (windowId: UInt32, ax: AxUiElementMock)

private func windowOrNil(_ any: Any?) -> WindowIdAndAxUiElementMock? {
    guard let any else { return nil }
    let potentialWindow = castToAxUiElementMock(any as AnyObject)
    // Filter out non-window objects (e.g. Finder's desktop)
    return switch potentialWindow.containingWindowId() {
    case let windowId?: (windowId, potentialWindow)
    case nil: nil
    }
}

extension AXUIElement: AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        let state = signposter.beginInterval(
            #function, "attr: \(attr.key) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        var raw: AnyObject?
        return unsafe AXUIElementCopyAttributeValue(self, attr.key as CFString, &raw) == .success
            ? raw.flatMap(attr.getter)
            : nil
    }

    @discardableResult func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool {
        if appOptions.isReadOnly { return false }
        let state = signposter.beginInterval(
            #function, "attr: \(attr.key) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        guard let value = attr.setter(value) else { return false }
        return AXUIElementSetAttributeValue(self, attr.key as CFString, value) == .success
    }

    func containingWindowId() -> CGWindowID? {
        let state = signposter.beginInterval(
            #function, "axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        var cgWindowId = CGWindowID()
        return unsafe _AXUIElementGetWindow(self, &cgWindowId) == .success && cgWindowId != kCGNullWindowID
            ? cgWindowId
            : nil
    }
}
