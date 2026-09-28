import AppKit
import Common

/// A gesture owns its source snapshot until release. Destination layouts are only previewed.
@MainActor final class MouseTiling {
    static let shared = MouseTiling()
    struct Preview {
        let workspace: Workspace
        let frame: Rect
        let floating: Bool
    }
    private struct Gesture {
        let window: Window
        let workspace: Workspace
        let kind: WindowKind
        let original: BinaryLayout
        let frame: Rect
        let bounds: Rect
        let gap: CGFloat
        var expected: BinaryLayout
        var resizing = false
        var hasRearranged = false
        var windowSwapMode = false
        var lastTargetRegion: Rect?
    }
    private var gesture: Gesture?
    private var blockedUntilRelease = false
    private(set) var preview: Preview?
    var isHandlingPointer: Bool { gesture != nil || blockedUntilRelease }

    /// Independent lifecycle edits call this *before* mutating membership.
    func cancel() {
        if let current = validGesture() {
            current.workspace.layout = current.original
            if current.kind == .floating { current.window.setAxFrame(current.frame.topLeftCorner, current.frame.size) }
            blockedUntilRelease = isLeftMouseButtonDown
        }
        clear()
    }
    private func clear() {
        gesture = nil
        preview = nil
        currentlyManipulatedWithMouseWindowId = nil
        if self === Self.shared { DragPreview.shared.hide() }
    }

    func observe(_ window: Window, frame: Rect, resizing: Bool) {
        guard !blockedUntilRelease, window.isRegistered, window.kind == .tiled || window.kind == .floating,
            let workspace = window.workspace
        else { return }
        if gesture == nil {
            let original = window.lastAppliedLayoutPhysicalRect ?? workspace.tiledFrames[window.windowId] ?? frame
            gesture = Gesture(
                window: window, workspace: workspace, kind: window.kind, original: workspace.layout,
                frame: original, bounds: workspace.layoutRect, gap: CGFloat(config.gap), expected: workspace.layout)
        }
        guard var current = validGesture(), current.window === window else { return }
        currentlyManipulatedWithMouseWindowId = window.windowId
        current.resizing =
            current.resizing
            || (!current.hasRearranged && resizing
                && (abs(frame.width - current.frame.width) > 5 || abs(frame.height - current.frame.height) > 5))
        if current.resizing && current.kind == .tiled {
            var layout = current.original
            let edges: [(CardinalDirection, CGFloat)] = [
                (.left, frame.minX - current.frame.minX), (.right, frame.maxX - current.frame.maxX),
                (.up, frame.minY - current.frame.minY), (.down, frame.maxY - current.frame.maxY),
            ]
            for (edge, delta) in edges where abs(delta) > 5 {
                layout.resizeEdge(
                    window.windowId, edge: edge, by: delta, in: current.bounds,
                    gap: current.gap, minimums: workspace.minimums)
            }
            workspace.layout = layout
            current.expected = layout
        }
        gesture = current
    }

    private func validGesture() -> Gesture? {
        guard let current = gesture else { return nil }
        guard current.window.isRegistered, current.window.kind == current.kind,
            current.window.workspace === current.workspace, current.window.layoutState.contains(current.workspace),
            current.expected == current.workspace.layout,
            current.bounds.size == current.workspace.layoutRect.size,
            current.bounds.topLeftCorner == current.workspace.layoutRect.topLeftCorner,
            current.gap == CGFloat(config.gap)
        else {
            clear()
            return nil
        }
        return current
    }

    func drag(at point: CGPoint, on destination: Workspace) {
        guard var current = validGesture(), !current.resizing,
            current.window.layoutState.contains(destination)
        else { return }
        if destination !== current.workspace {
            var layout = destination.layout
            var minimums = destination.minimums
            minimums[current.window.windowId] = current.window.minimumSize
            let tiled =
                current.kind == .tiled
                && layout.insert(
                    current.window.windowId, beside: destination.insertionTarget,
                    placement: config.newWindowPlacement, in: destination.layoutRect, gap: CGFloat(config.gap),
                    minimums: minimums)
            let frame =
                tiled
                ? layout.frames(in: destination.layoutRect, gap: CGFloat(config.gap))[current.window.windowId]!
                : Rect(
                    topLeftX: point.x - current.frame.width / 2, topLeftY: point.y - 20,
                    width: current.frame.width, height: current.frame.height)
            preview = Preview(workspace: destination, frame: frame, floating: !tiled)
            if self === Self.shared { DragPreview.shared.show(frame, floating: !tiled) }
            return
        }
        preview = nil
        if self === Self.shared { DragPreview.shared.hide() }
        guard current.kind == .tiled else { return }
        if current.lastTargetRegion?.contains(point) == true { return }
        current.lastTargetRegion = nil
        let window = current.window
        let parent = destination.layout.parent(of: window.windowId, in: current.bounds, gap: current.gap)
        let section = !current.windowSwapMode && parent?.rect.contains(point) == true
        let target: UInt32
        let rect: Rect
        if section {
            guard let parent,
                let sibling = siblingRegion(
                    of: window.windowId, in: current.expected, bounds: current.bounds, gap: current.gap),
                let sourceFrame = destination.tiledFrames[window.windowId],
                let siblingId = parent.ids.first(where: { $0 != window.windowId })
            else {
                gesture = current
                return
            }
            let projected =
                parent.axis == .h
                ? CGPoint(x: point.x, y: sourceFrame.center.y) : CGPoint(x: sourceFrame.center.x, y: point.y)
            guard sibling.contains(projected) else {
                gesture = current
                return
            }
            target = siblingId
            rect = sibling
        } else {
            guard
                let hit = destination.tiledFrames.sorted(by: { $0.key < $1.key }).first(where: {
                    $0.value.contains(point)
                }),
                hit.key != window.windowId
            else {
                gesture = current
                return
            }
            target = hit.key
            rect = hit.value
        }
        if destination.layout.swap(
            window.windowId, with: target, section: section,
            in: current.bounds, gap: current.gap, minimums: destination.minimums)
        {
            current.lastTargetRegion = rect
            current.windowSwapMode = current.windowSwapMode || !section
            current.hasRearranged = true
            current.expected = destination.layout
            _ = window.focusWindow()
        }
        gesture = current
    }

    private func siblingRegion(of id: UInt32, in layout: BinaryLayout, bounds: Rect, gap: CGFloat) -> Rect? {
        let geometry = layout.geometry(in: bounds, gap: gap)
        guard let leaf = geometry.leaves.first(where: { $0.id == id }), !leaf.path.isEmpty else { return nil }
        var siblingPath = leaf.path
        siblingPath[siblingPath.count - 1].toggle()
        return geometry.sections.first { $0.path == siblingPath }?.rect
            ?? geometry.leaves.first { $0.path == siblingPath }?.rect
    }

    func finish(at point: CGPoint, on destination: Workspace) {
        defer {
            clear()
            blockedUntilRelease = false
        }
        guard let current = validGesture() else { return }
        if !current.resizing, destination !== current.workspace, current.window.layoutState.contains(destination) {
            // Discard all incidental live swaps on the source before doing one transfer.
            current.workspace.layout = current.original
            clear()
            current.window.layoutState.place(current.window, on: destination, kind: current.kind)
            _ = current.window.focusWindow()
        } else {
            drag(at: point, on: current.workspace)
        }
    }
}

/// Non-activating outline; the real target tree is untouched until the mouse is released.
@MainActor private final class DragPreview {
    static let shared = DragPreview()
    private var panel: NSPanel?
    func show(_ rect: Rect, floating: Bool) {
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
    func hide() { panel?.orderOut(nil) }
}
