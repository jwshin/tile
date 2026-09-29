import Carbon
import Observation

@MainActor @Observable
public final class TrayMenuModel {
    public static let shared = TrayMenuModel()
    private init() {}
    let launchAtLogin = LaunchAtLogin(service: NativeLoginItemService())
    var trayText = "tile"
    var isEnabled: Bool { ConfigurationApplication.shared.isEnabled }
    var axPermissionStatus: AxPermissionStatus = .waitingWithPrompt
    var secureInput = false
}

enum AxPermissionStatus: Equatable { case granted, waiting, waitingWithPrompt }

@MainActor func updateTrayText() {
    let model = TrayMenuModel.shared
    model.secureInput = IsSecureEventInputEnabled()
    model.trayText = model.secureInput ? "tile 🔒" : "tile"
}
