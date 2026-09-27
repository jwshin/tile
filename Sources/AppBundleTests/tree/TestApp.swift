import Common

@testable import AppBundle

final class TestApp: AbstractApp {
    let pid: Int32
    var isHidden = false
    let name: String?
    @MainActor
    static let shared = TestApp()

    private init() {
        self.pid = 0
        self.name = "tile test app"
    }

    var _windows: [Window] = []
    var windows: [Window] {
        get { _windows }
        set {
            if let focusedWindow {
                check(newValue.contains(focusedWindow))
            }
            _windows = newValue
        }
    }

    private var _focusedWindow: Window? = nil
    var focusedWindow: Window? {
        get { _focusedWindow }
        set {
            if let window = newValue {
                check(windows.contains(window))
            }
            _focusedWindow = newValue
        }
    }
    @MainActor func getFocusedWindow(_ cm: CancellationMode) -> Window? { _focusedWindow }
}
