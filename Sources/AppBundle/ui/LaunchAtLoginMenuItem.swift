import ServiceManagement
import SwiftUI

struct LaunchAtLoginMenuItem: View {
    let model: LaunchAtLogin

    var body: some View {
        Group {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { model.isEnabled },
                    set: { enabled in
                        if let diagnostic = model.setEnabled(enabled) {
                            MessageModel.shared.message = Message(body: diagnostic)
                        }
                    })
            )
            .disabled(model.status == .notFound)
            .help("Automatically open tile when you log in to this Mac.")
            if model.status == .requiresApproval {
                Button("Allow Launch at Login…") { model.openSettings() }
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            model.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}
