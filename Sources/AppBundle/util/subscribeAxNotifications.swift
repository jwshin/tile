import AppKit

struct AxSubscriptionBatch<Subscription> {
    var subscriptions: [Subscription] = []
    var failures: [String] = []
    var pending: [AxNotificationRetry<Subscription>] = []

    mutating func deferAttempts(_ attempts: ArraySlice<AxNotificationRetry<Subscription>>) {
        pending.append(contentsOf: attempts)
        failures.append(contentsOf: attempts.map(\.deferredDiagnostic))
    }
}

struct AxNotificationRetry<Subscription> {
    let mappingIndex: Int
    let keys: [String]
    let subscription: Subscription?

    var deferredDiagnostic: String {
        "Deferred notification setup (\(keys.joined(separator: ", "))): earlier AX request could not complete."
    }
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
    for (attemptIndex, attempt) in pending.enumerated() {
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
                if error == .cannotComplete {
                    try job.checkCancellation()
                    result.deferAttempts(pending.dropFirst(attemptIndex + 1))
                    return result
                }
                continue
            }
            subscription = created
        }
        var failedKeys: [String] = []
        var stalled = false
        for (keyIndex, key) in attempt.keys.enumerated() {
            try job.checkCancellation()
            let error = subscribe(subscription, key)
            if error != .success {
                result.failures.append("\(key): error=\(error.rawValue)")
                failedKeys.append(key)
                if error == .cannotComplete {
                    let deferredKeys = Array(attempt.keys.dropFirst(keyIndex + 1))
                    failedKeys.append(contentsOf: deferredKeys)
                    if !deferredKeys.isEmpty {
                        result.failures.append(
                            AxNotificationRetry(
                                mappingIndex: attempt.mappingIndex, keys: deferredKeys, subscription: subscription
                            ).deferredDiagnostic)
                    }
                    stalled = true
                    break
                }
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
        if stalled {
            result.deferAttempts(pending.dropFirst(attemptIndex + 1))
            return result
        }
    }
    return result
}
