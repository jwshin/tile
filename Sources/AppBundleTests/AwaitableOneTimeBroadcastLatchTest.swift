import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    struct AwaitableOneTimeBroadcastLatchTest {
        var name: String { String(describing: Self.self) }
        @Test func testAwaitAfterSignalReturnsImmediately() async throws {
            let latch = AwaitableOneTimeBroadcastLatch()
            await latch.signalToAll()
            try await latch.await()
        }

        @Test func testAwaitOnFreshLatchSuspendsUntilSignal() async throws {
            let latch = AwaitableOneTimeBroadcastLatch()
            let task = Task { try await latch.await() }
            try await Task.sleep(for: .milliseconds(50))
            assertFalse(task.isCancelled)
            await latch.signalToAll()
            try await task.value
        }

        @Test func testSignalReleasesAllPendingAwaiters() async throws {
            let latch = AwaitableOneTimeBroadcastLatch()
            let count = 20
            let tasks = (0..<count).map { _ in Task { try await latch.await() } }
            try await Task.sleep(for: .milliseconds(50))
            await latch.signalToAll()
            for task in tasks { try await task.value }
        }

        @Test func testSignalIsIdempotent() async throws {
            let latch = AwaitableOneTimeBroadcastLatch()
            await latch.signalToAll()
            await latch.signalToAll()
            await latch.signalToAll()
            try await latch.await()
            try await latch.await()
        }

        @Test func testSignalWithNoAwaiters() async throws {
            let latch = AwaitableOneTimeBroadcastLatch()
            await latch.signalToAll()
            try await latch.await()
        }

        @Test func testCancellingPendingAwaiterThrows() async throws {
            let latch = AwaitableOneTimeBroadcastLatch()
            let task = Task { try await latch.await() }
            try await Task.sleep(for: .milliseconds(50))
            task.cancel()
            await assertThrowsCancellation(task)
        }

        @Test func testCancellingOneAwaiterDoesNotAffectOthers() async throws {
            let latch = AwaitableOneTimeBroadcastLatch()
            let cancelled = Task { try await latch.await() }
            let survivors = (0..<5).map { _ in Task { try await latch.await() } }
            try await Task.sleep(for: .milliseconds(50))
            cancelled.cancel()
            await assertThrowsCancellation(cancelled)
            await latch.signalToAll()
            for task in survivors { try await task.value }
        }

        @Test func testAwaitBailsWhenTaskIsAlreadyCancelled() async {
            let latch = AwaitableOneTimeBroadcastLatch()
            let task = Task { () async throws in
                while !Task.isCancelled { await Task.yield() }
                try await latch.await()
            }
            task.cancel()
            await assertThrowsCancellation(task)
        }

        @Test func testSignalAfterCancellationStillReleasesRemainingAwaiters() async throws {
            let latch = AwaitableOneTimeBroadcastLatch()
            let cancelled = Task { try await latch.await() }
            let lateJoiner = Task { try await latch.await() }
            try await Task.sleep(for: .milliseconds(50))
            cancelled.cancel()
            await assertThrowsCancellation(cancelled)
            await latch.signalToAll()
            try await lateJoiner.value
            // New await arriving after the signal still returns immediately.
            try await latch.await()
        }

        private func assertThrowsCancellation<T: Sendable>(
            _ task: Task<T, any Error>, file: StaticString = #filePath, line: UInt = #line
        ) async {
            do {
                _ = try await task.value
                failExpectedActual("CancellationError", "no error thrown", file: file, line: line)
            } catch is CancellationError {
                // expected
            } catch {
                failExpectedActual("CancellationError", error, file: file, line: line)
            }
        }
    }
}
