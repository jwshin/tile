import Foundation
import Testing

@testable import AppBundle

extension CoreTests {
    struct RunLoopJobTest {
        @Test func appLoopAcceptsWindowReadsWithoutAnyAccessibilityObservers() async throws {
            let ready = AwaitableOneTimeBroadcastLatch()
            let finished = AwaitableOneTimeBroadcastLatch()
            let thread = Thread {
                let appRunLoop = AxAppRunLoop()
                Task { await ready.signalToAll() }
                appRunLoop.run()
                Task { await finished.signalToAll() }
            }
            thread.start()
            try await ready.await()
            let value = try await thread.runInLoop(.nonCancellable) { _ in
                CFRunLoopStop(CFRunLoopGetCurrent())
                return 5930
            }
            #expect(value == 5930)
            try await finished.await()
        }

        @Test func cancellationIsVisibleAcrossThreads() throws {
            let job = RunLoopJob(.cancellable)
            #expect(!job.isCancelled)
            try job.checkCancellation()
            DispatchQueue.concurrentPerform(iterations: 64) { index in
                if index.isMultiple(of: 2) {
                    job.cancel()
                } else {
                    _ = job.isCancelled
                }
            }
            #expect(job.isCancelled)
            #expect(throws: CancellationError.self) { try job.checkCancellation() }
        }

        @Test func nonCancellableJobSurvivesConcurrentCancellation() throws {
            let job = RunLoopJob(.nonCancellable)
            DispatchQueue.concurrentPerform(iterations: 64) { _ in job.cancel() }
            #expect(!job.isCancelled)
            try job.checkCancellation()
        }
    }
}
