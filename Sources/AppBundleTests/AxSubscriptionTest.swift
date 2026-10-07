import AppKit
import Testing

@testable import AppBundle

extension CoreTests {
    struct AxSubscriptionTest {
        @Test func refreshRetriesOnlyFailedKeysAndClearsRecoveredDiagnostics() throws {
            let mappings = [(0, ["AXWindowCreated", "AXFocusedWindowChanged"]), (1, ["AXMoved", "AXResized"])]
            var created: [Int] = []
            var attempted: [String] = []
            var activated: [Int] = []
            let initial = try subscribeAxNotifications(
                mappings, job: RunLoopJob(.nonCancellable),
                create: {
                    created.append($0)
                    return ($0, .success)
                },
                subscribe: { _, key in key == "AXWindowCreated" || key == "AXMoved" ? .apiDisabled : .success },
                activate: { activated.append($0) })
            let recovered = try subscribeAxNotifications(
                mappings, job: RunLoopJob(.nonCancellable), retrying: initial,
                create: {
                    created.append($0)
                    return ($0, .success)
                },
                subscribe: { _, key in
                    attempted.append(key)
                    return .success
                },
                activate: { activated.append($0) })
            #expect(created == [0, 1])
            #expect(activated == [0, 1])
            #expect(attempted == ["AXWindowCreated", "AXMoved"])
            #expect(recovered.subscriptions == [0, 1])
            #expect(recovered.failures.isEmpty)
            attempted = []
            let repeated = try subscribeAxNotifications(
                mappings, job: RunLoopJob(.nonCancellable), retrying: recovered, create: { ($0, .success) },
                subscribe: { _, key in
                    attempted.append(key)
                    return .success
                }, activate: { _ in })
            #expect(attempted.isEmpty)
            #expect(repeated.subscriptions == [0, 1])
        }

        @Test func refreshRetriesFailedObserverWithoutReplacingWorkingHandlers() throws {
            let mappings = [(0, ["AXMoved"]), (1, ["AXResized"])]
            let initial = try subscribeAxNotifications(
                mappings, job: RunLoopJob(.nonCancellable),
                create: { ($0 == 0 ? nil : $0, $0 == 0 ? .cannotComplete : .success) },
                subscribe: { _, _ in .success }, activate: { _ in })
            var created: [Int] = []
            var attempted: [String] = []
            let recovered = try subscribeAxNotifications(
                mappings, job: RunLoopJob(.nonCancellable), retrying: initial,
                create: {
                    created.append($0)
                    return ($0, .success)
                },
                subscribe: { _, key in
                    attempted.append(key)
                    return .success
                }, activate: { _ in })
            #expect(created == [0])
            #expect(attempted == ["AXMoved"])
            #expect(Set(recovered.subscriptions) == [0, 1])
            #expect(recovered.failures.isEmpty)
        }

        @Test func repeatedFailureKeepsItsObserverAndUpdatesCurrentErrors() throws {
            let mappings = [(0, ["AXWindowCreated", "AXFocusedWindowChanged"])]
            let initial = try subscribeAxNotifications(
                mappings, job: RunLoopJob(.nonCancellable), create: { ($0, .success) },
                subscribe: { _, _ in .apiDisabled }, activate: { _ in })
            var created = 0
            let retried = try subscribeAxNotifications(
                mappings, job: RunLoopJob(.nonCancellable), retrying: initial,
                create: {
                    created += 1
                    return ($0, .success)
                }, subscribe: { _, _ in .cannotComplete },
                activate: { _ in })
            #expect(created == 0)
            #expect(retried.subscriptions == [0])
            #expect(retried.failures == mappings[0].1.map { "\($0): error=\(AXError.cannotComplete.rawValue)" })
        }

        @Test func unsupportedNotificationKeepsSupportedAppAndWindowNotifications() throws {
            let mappings = [(0, ["AXWindowCreated", "AXFocusedWindowChanged"]), (1, ["AXMoved", "AXResized"])]
            var attempted: [String] = []
            var activated: [Int] = []
            let batch = try subscribeAxNotifications(
                mappings, job: RunLoopJob(.cancellable), create: { ($0, .success) },
                subscribe: { _, key in
                    attempted.append(key)
                    return key == "AXWindowCreated" || key == "AXMoved" ? .notificationUnsupported : .success
                }, activate: { activated.append($0) })
            #expect(batch.subscriptions == [0, 1])
            #expect(activated == [0, 1])
            #expect(attempted == mappings.flatMap(\.1))
            #expect(batch.failures.count == 2)
            #expect(batch.failures.contains("AXWindowCreated: error=\(AXError.notificationUnsupported.rawValue)"))
        }

        @Test func noSupportedNotificationsStillRetainsTheObserverForReadableWindows() throws {
            let batch = try subscribeAxNotifications(
                [(0, ["AXWindowCreated", "AXFocusedWindowChanged"])], job: RunLoopJob(.cancellable),
                create: { ($0, .success) }, subscribe: { _, _ in .cannotComplete }, activate: { _ in })
            #expect(batch.subscriptions == [0])
            #expect(batch.failures.count == 2)
        }

        @Test func observerCreationFailureDoesNotDiscardOtherHandlers() throws {
            var attempted: [Int] = []
            let batch = try subscribeAxNotifications(
                [(0, ["AXUIElementDestroyed"]), (1, ["AXMoved"]), (2, ["AXResized"])],
                job: RunLoopJob(.cancellable),
                create: { handler -> (Int?, AXError) in
                    attempted.append(handler)
                    return handler == 1 ? (nil, .cannotComplete) : (handler, .success)
                }, subscribe: { _, _ in .success }, activate: { _ in })
            #expect(batch.subscriptions == [0, 2])
            #expect(attempted == [0, 1, 2])
            #expect(batch.failures == ["AXObserverCreate (AXMoved): error=\(AXError.cannotComplete.rawValue)"])
        }

        @Test func cancellationStopsSetupBeforeSubmittingMoreNativeCalls() throws {
            let job = RunLoopJob(.cancellable)
            var attempted: [String] = []
            #expect(throws: CancellationError.self) {
                try subscribeAxNotifications(
                    [(0, ["AXMoved", "AXResized"])], job: job, create: { ($0, .success) },
                    subscribe: { _, key in
                        attempted.append(key)
                        job.cancel()
                        return .success
                    }, activate: { _ in })
            }
            #expect(attempted == ["AXMoved"])
        }
    }
}
