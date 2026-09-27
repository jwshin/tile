import Carbon
import Observation

@MainActor @Observable
public final class TrayMenuModel {
    public static let shared = TrayMenuModel()
    private init() {}
    var trayText = "tile"
    var isEnabled = true
    var axPermissionStatus: AxPermissionStatus = .waitingWithPrompt
    var secureInput = false
}

enum AxPermissionStatus: Equatable { case granted, waiting, waitingWithPrompt }

@MainActor func updateTrayText() {
    let model = TrayMenuModel.shared
    model.secureInput = IsSecureEventInputEnabled()
    model.trayText = model.secureInput ? "tile 🔒" : "tile"
}
