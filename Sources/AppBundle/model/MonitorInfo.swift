import AppKit
import Common

private struct MonitorInfoImpl {
    let displayId: String
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
}

extension MonitorInfoImpl: MonitorInfo {
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

/// Use it instead of NSScreen because it can be mocked in tests
protocol MonitorInfo: TileValue {
    var displayId: String { get }
    var name: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
    var isMain: Bool { get }
}

final class LazyMonitorInfo: MonitorInfo {
    private let screen: NSScreen
    let name: String
    let displayId: String
    let width: CGFloat
    let height: CGFloat
    let isMain: Bool
    private var _rect: Rect?
    private var _visibleRect: Rect?

    init(isMain: Bool, _ screen: NSScreen) {
        self.name = screen.localizedName
        self.width = screen.frame.width  // Don't call rect because it would cause recursion during mainMonitor init
        self.height = screen.frame.height  // Don't call rect because it would cause recursion during mainMonitor init
        self.screen = screen
        self.displayId = screen.displayId
        self.isMain = isMain
    }

    var rect: Rect {
        _rect ?? screen.rect.also { _rect = $0 }
    }

    var visibleRect: Rect {
        _visibleRect ?? screen.visibleRect.also { _visibleRect = $0 }
    }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    fileprivate var displayId: String {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? localizedName
    }

    fileprivate func toMonitorInfo() -> MonitorInfo {
        MonitorInfoImpl(
            displayId: displayId,
            name: localizedName,
            rect: rect,
            visibleRect: visibleRect,
            isMain: isMainScreen,
        )
    }

    fileprivate var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }

    /// The property is a replacement for Apple's crazy ``frame``
    ///
    /// - For ``MacWindow.topLeftCorner``, (0, 0) is main screen top left corner, and positive y-axis goes down.
    /// - For ``frame``, (0, 0) is main screen bottom left corner, and positive y-axis goes up (which is crazy).
    ///
    /// The property "normalizes" ``frame``
    fileprivate var rect: Rect { frame.monitorFrameNormalized() }

    /// Same as ``rect`` but for ``visibleFrame``
    fileprivate var visibleRect: Rect { visibleFrame.monitorFrameNormalized() }
}

private let testMonitorInfoRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
private let testMonitorInfo = MonitorInfoImpl(
    displayId: "test-main",
    name: "Test Monitor",
    rect: testMonitorInfoRect,
    visibleRect: testMonitorInfoRect,
    isMain: true,
)

nonisolated(unsafe) var testMonitors: [MonitorInfo]? = nil

var mainMonitorInfo: MonitorInfo {
    if let testMonitors = unsafe testMonitors {
        return testMonitors.first(where: \.isMain) ?? testMonitors.first ?? testMonitorInfo
    }
    if isUnitTest { return testMonitorInfo }
    let screens = NSScreen.screens
    // Fallback: If main screen can't be found (e.g., during display reconfiguration),
    // return screens.first or testMonitor to avoid crash
    let screen = screens.singleOrNil(where: \.isMainScreen) ?? screens.first
    guard let screen else { return testMonitorInfo }
    return LazyMonitorInfo(isMain: true, screen)
}

var monitorInfos: [MonitorInfo] {
    if let testMonitors = unsafe testMonitors { return testMonitors }
    return isUnitTest
        ? [testMonitorInfo]
        : NSScreen.screens.map { $0.toMonitorInfo() }
}

var sortedMonitorInfos: [MonitorInfo] {
    monitorInfos.sortedBy([\.rect.minX, \.rect.minY])
}
