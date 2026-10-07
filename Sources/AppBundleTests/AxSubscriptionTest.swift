import AppKit
import Testing

@testable import AppBundle

extension CoreTests {
    struct AxSubscriptionTest {
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
