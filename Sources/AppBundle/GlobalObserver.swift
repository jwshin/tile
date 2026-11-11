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
        // Process power events even while tiling is disabled. Main-queue delivery closes the gate
        // before subsequently queued AX/display callbacks can reconcile a partial topology.
        for (name, reason, sleeping) in [
            (NSWorkspace.willSleepNotification, DisplayRecovery.Reason.system, true),
            (NSWorkspace.didWakeNotification, .system, false),
            (NSWorkspace.screensDidSleepNotification, .screens, true),
            (NSWorkspace.screensDidWakeNotification, .screens, false),
        ] {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if sleeping {
                        ActionExecution.shared.displayWillSleep(reason)
                    } else {
                        ActionExecution.shared.displayDidWake(reason)
                    }
                }
            }
        }
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif)

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return }
            handleEscapeKey()
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { handleEscapeKey() }
            return event
        }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            handleLeftMouseDown()
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            handleLeftMouseDown()
            return event
        }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            handleLeftMouseUp()
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            handleLeftMouseUp()
            return event
        }
    }

    private static func handleEscapeKey() {
        _ = Task { @MainActor in
            guard DisplayLayoutState.shared.isHandlingPointer else { return }
            DisplayLayoutState.shared.cancelPointer()
            if ConfigurationApplication.shared.isEnabled {
                ActionExecution.shared.scheduleRefresh(.resetManipulatedWithMouse)
            }
        }
    }

    private static func handleLeftMouseDown() {
        _ = Task { @MainActor in
            DisplayLayoutState.shared.resetMissedPointerRelease()
        }
    }

    private static func handleLeftMouseUp() {
        _ = Task { @MainActor in
            let didResetPointer = try await resetManipulatedWithMouseIfPossible()
            guard ConfigurationApplication.shared.isEnabled, !didResetPointer else { return }
            // Detect close button clicks for unfocused windows and trigger new window detection
            // that was deferred while the mouse button remained pressed.
            ActionExecution.shared.scheduleRefresh(.globalObserverLeftMouseUp)
        }
    }
}
