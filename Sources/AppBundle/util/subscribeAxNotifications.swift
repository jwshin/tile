import AppKit

struct AxSubscriptionBatch<Subscription> {
    var subscriptions: [Subscription] = []
    var failures: [String] = []
}

/// Notifications accelerate discovery; a failed notification must not gate readable windows.
func subscribeAxNotifications<Handler, Subscription>(
    _ mappings: [(Handler, [String])],
    job: RunLoopJob,
    create: (Handler) -> (Subscription?, AXError),
    subscribe: (Subscription, String) -> AXError,
    activate: (Subscription) -> Void,
) throws -> AxSubscriptionBatch<Subscription> {
    var result = AxSubscriptionBatch<Subscription>()
    for (handler, keys) in mappings {
        try job.checkCancellation()
        let (subscription, error) = create(handler)
        guard let subscription else {
            result.failures.append("AXObserverCreate (\(keys.joined(separator: ", "))): error=\(error.rawValue)")
            continue
        }
        for key in keys {
            try job.checkCancellation()
            let error = subscribe(subscription, key)
            if error != .success {
                result.failures.append("\(key): error=\(error.rawValue)")
            }
        }
        try job.checkCancellation()
        activate(subscription)
        result.subscriptions.append(subscription)
    }
    return result
}
