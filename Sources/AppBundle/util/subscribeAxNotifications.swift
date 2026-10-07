import AppKit

struct AxSubscriptionBatch<Subscription> {
    var subscriptions: [Subscription] = []
    var failures: [String] = []
    var pending: [AxNotificationRetry<Subscription>] = []
}

struct AxNotificationRetry<Subscription> {
    let mappingIndex: Int
    let keys: [String]
    let subscription: Subscription?
}

/// Notifications accelerate discovery; a failed notification must not gate readable windows.
func subscribeAxNotifications<Handler, Subscription>(
    _ mappings: [(Handler, [String])],
    job: RunLoopJob,
    retrying previous: AxSubscriptionBatch<Subscription>? = nil,
    create: (Handler) -> (Subscription?, AXError),
    subscribe: (Subscription, String) -> AXError,
    activate: (Subscription) -> Void,
) throws -> AxSubscriptionBatch<Subscription> {
    var result = AxSubscriptionBatch<Subscription>()
    result.subscriptions = previous?.subscriptions ?? []
    let pending =
        previous?.pending
        ?? mappings.enumerated().map {
            AxNotificationRetry<Subscription>(mappingIndex: $0.offset, keys: $0.element.1, subscription: nil)
        }
    for attempt in pending {
        try job.checkCancellation()
        let subscription: Subscription
        if let existing = attempt.subscription {
            subscription = existing
        } else {
            let (created, error) = create(mappings[attempt.mappingIndex].0)
            guard let created else {
                result.failures.append(
                    "AXObserverCreate (\(attempt.keys.joined(separator: ", "))): error=\(error.rawValue)")
                result.pending.append(attempt)
                continue
            }
            subscription = created
        }
        var failedKeys: [String] = []
        for key in attempt.keys {
            try job.checkCancellation()
            let error = subscribe(subscription, key)
            if error != .success {
                result.failures.append("\(key): error=\(error.rawValue)")
                failedKeys.append(key)
            }
        }
        try job.checkCancellation()
        if attempt.subscription == nil {
            activate(subscription)
            result.subscriptions.append(subscription)
        }
        if !failedKeys.isEmpty {
            result.pending.append(
                AxNotificationRetry(
                    mappingIndex: attempt.mappingIndex, keys: failedKeys, subscription: subscription))
        }
    }
    return result
}
