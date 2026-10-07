import AppKit
import Common

/// The subscription is active as long as you keep this class in memory
final class AxSubscription {
    let obs: AXObserver
    let ax: AXUIElement
    let axThreadToken: AxAppThreadToken =
        axTaskLocalAppThreadToken ?? dieT("axTaskLocalAppThreadToken is not initialized")
    var notifKeys: Set<String> = []

    private init(obs: AXObserver, ax: AXUIElement) {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        self.obs = obs
        self.ax = ax
    }

    private func subscribe(_ key: String) -> AXError {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        let error = AXObserverAddNotification(obs, ax, key as CFString, nil)
        if error == .success {
            notifKeys.insert(key)
        }
        return error
    }

    static func bulkSubscribe(
        _ nsApp: NSRunningApplication,
        _ ax: AXUIElement,
        _ job: RunLoopJob,
        _ handlerToNotifKeyMapping: HandlerToNotifKeyMapping,
    ) throws -> AxSubscriptionBatch<AxSubscription> {
        var visitedNotifKeys: Set<String> = []
        return try unsafe subscribeAxNotifications(
            handlerToNotifKeyMapping, job: job,
            create: { handler in
                var observer: AXObserver?
                let error = unsafe AXObserverCreate(nsApp.processIdentifier, handler, &observer)
                return (observer.map { AxSubscription(obs: $0, ax: ax) }, error)
            },
            subscribe: { subscription, key in
                assert(visitedNotifKeys.insert(key).inserted)
                return subscription.subscribe(key)
            },
            activate: { subscription in
                CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(subscription.obs), .defaultMode)
            })
    }

    deinit {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        for notifKey in notifKeys {
            AXObserverRemoveNotification(obs, ax, notifKey as CFString)
        }
    }
}

typealias HandlerToNotifKeyMapping = [(AXObserverCallback, [String])]
