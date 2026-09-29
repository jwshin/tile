import AppKit
import Common

/// Native pointer input and preview effects; each display layout state owns its adapter.
@MainActor protocol PointerAdapter {
    var isButtonDown: Bool { get }
    func showPreview(_ preview: MouseTiling.Preview?)
}

/// Non-activating outline; the real target tree is untouched until the mouse is released.
@MainActor final class NativePointerAdapter: PointerAdapter {
    private var panel: NSPanel?
    var isButtonDown: Bool { isLeftMouseButtonDown }

    func showPreview(_ preview: MouseTiling.Preview?) {
        guard let preview else {
            panel?.orderOut(nil)
            return
        }
        let rect = preview.frame
        let floating = preview.floating
        guard !isUnitTest, !appOptions.isReadOnly else { return }
        if panel == nil {
            let panel = NSPanel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSView()
            panel.contentView?.wantsLayer = true
            self.panel = panel
        }
        let color = floating ? NSColor.systemOrange : NSColor.systemBlue
        panel?.contentView?.layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
        panel?.contentView?.layer?.borderColor = color.cgColor
        panel?.contentView?.layer?.borderWidth = 3
        panel?.setFrame(
            CGRect(x: rect.minX, y: mainMonitorInfo.height - rect.maxY, width: rect.width, height: rect.height),
            display: true)
        panel?.orderFrontRegardless()
    }
}
