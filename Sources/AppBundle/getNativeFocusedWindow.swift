import AppKit

@MainActor func getNativeFocusedWindow(_ cm: CancellationMode) async throws -> Window? {
    guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
    return try await MacApp.getOrRegister(application)?.getFocusedWindow(cm)
}
