import AppKit
import Common

enum GlobalObserver {
    private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: DisplayLayoutState restoration
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            == lockScreenAppBundleId
        {
            return
        }
        let notifName = notification.name.rawValue
        _ = Task { @MainActor in
            if !TrayMenuModel.shared.isEnabled { return }
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue {
                ActionExecution.shared.scheduleRefresh(
                    .globalObserver(notifName), optimisticallyPreLayoutWorkspaces: true)
            } else {
                ActionExecution.shared.scheduleRefresh(.globalObserver(notifName))
            }
        }
    }

    @MainActor
    static func initObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: onNotif)
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif)

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            // todo reduce number of refresh session in the callback
            //  resetManipulatedWithMouseIfPossible might call its own refresh session
            //  The end of the callback calls refresh session
            _ = Task { @MainActor in
                guard let token: RunSessionGuard = .isEnabled else { return }
                try await resetManipulatedWithMouseIfPossible()
                let mouseLocation = mouseLocation
                let clickedMonitor = mouseLocation.monitorApproximation
                switch true {
                // Detect clicks on desktop of different monitors
                case clickedMonitor.visibleRect.contains(mouseLocation)
                    && clickedMonitor.activeWorkspace != focus.workspace:
                    _ = try await ActionExecution.shared.runSession(.globalObserverLeftMouseUp, token) {
                        clickedMonitor.activeWorkspace.focusWorkspace()
                    }
                // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                //  And trigger new window detection that could be delayed due to mouseDown event
                default:
                    ActionExecution.shared.scheduleRefresh(.globalObserverLeftMouseUp)
                }
            }
        }
    }
}
