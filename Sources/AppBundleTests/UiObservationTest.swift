import Observation
import Synchronization
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct UiObservationTest {
        @Test func messageChangesInvalidateObservation() {
            let model = MessageModel.shared
            let original = model.message
            defer { model.message = original }
            model.message = nil
            let changed = Atomic<Bool>(false)
            withObservationTracking {
                _ = model.message
            } onChange: {
                changed.store(true, ordering: .relaxed)
            }
            model.message = Message(body: "Config test")
            let didChange = changed.load(ordering: .relaxed)
            #expect(didChange)
        }

        @Test func enableChangesInvalidateMenuObservation() {
            let model = TrayMenuModel.shared
            let original = model.isEnabled
            defer { model.isEnabled = original }
            let changed = Atomic<Bool>(false)
            withObservationTracking {
                _ = model.isEnabled
            } onChange: {
                changed.store(true, ordering: .relaxed)
            }
            model.isEnabled.toggle()
            let didChange = changed.load(ordering: .relaxed)
            #expect(didChange)
        }
    }
}
