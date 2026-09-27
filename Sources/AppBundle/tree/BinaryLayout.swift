import AppKit
import Common

/// A value tree: every split has exactly two children. Only this module edits nodes.
struct BinaryLayout: Equatable {
    private indirect enum Node: Equatable {
        case window(UInt32)
        case split(Orientation, CGFloat, Node, Node)

        var ids: [UInt32] {
            switch self {
            case .window(let id): [id]
            case .split(_, _, let first, let second): first.ids + second.ids
            }
        }

        func replacing(_ id: UInt32, with replacement: Node) -> Node {
            switch self {
            case .window(let existing): existing == id ? replacement : self
            case .split(let axis, let ratio, let first, let second):
                .split(axis, ratio, first.replacing(id, with: replacement), second.replacing(id, with: replacement))
            }
        }

        func retaining(_ ids: Set<UInt32>) -> Node? {
            switch self {
            case .window(let id): ids.contains(id) ? self : nil
            case .split(let axis, let ratio, let first, let second):
                switch (first.retaining(ids), second.retaining(ids)) {
                case (let a?, let b?): .split(axis, ratio, a, b)
                case (let a?, nil): a
                case (nil, let b?): b
                case (nil, nil): nil
                }
            }
        }

        func frames(in rect: Rect, gap: CGFloat, into result: inout [UInt32: Rect]) {
            switch self {
            case .window(let id): result[id] = rect
            case .split(let axis, let ratio, let first, let second):
                let (a, b) = BinaryLayout.divide(rect, axis: axis, ratio: ratio, gap: gap)
                first.frames(in: a, gap: gap, into: &result)
                second.frames(in: b, gap: gap, into: &result)
            }
        }

        func swapping(_ a: UInt32, _ b: UInt32) -> Node {
            switch self {
            case .window(let id): .window(id == a ? b : id == b ? a : id)
            case .split(let axis, let ratio, let first, let second):
                .split(axis, ratio, first.swapping(a, b), second.swapping(a, b))
            }
        }

        func balanced() -> Node {
            switch self {
            case .window: self
            case .split(let axis, _, let first, let second):
                .split(axis, CGFloat(first.ids.count) / CGFloat(ids.count), first.balanced(), second.balanced())
            }
        }

        /// Visit the target's ancestors from nearest to farthest, changing at most one split.
        func editingSplit(
            for id: UInt32, in rect: Rect, gap: CGFloat,
            edit: (Orientation, CGFloat, Bool, Rect) -> (Orientation, CGFloat)?
        ) -> (Node, Bool) {
            guard case .split(let axis, let ratio, let first, let second) = self else { return (self, false) }
            let inFirst = first.ids.contains(id)
            guard inFirst || second.ids.contains(id) else { return (self, false) }
            let (a, b) = BinaryLayout.divide(rect, axis: axis, ratio: ratio, gap: gap)
            let (child, changed) = (inFirst ? first : second).editingSplit(
                for: id, in: inFirst ? a : b, gap: gap, edit: edit)
            if changed { return (.split(axis, ratio, inFirst ? child : first, inFirst ? second : child), true) }
            guard let (newAxis, newRatio) = edit(axis, ratio, inFirst, rect) else { return (self, false) }
            return (.split(newAxis, newRatio, first, second), true)
        }
    }

    private var root: Node?
    var windowIds: [UInt32] { root?.ids ?? [] }

    func frames(in rect: Rect, gap: CGFloat) -> [UInt32: Rect] {
        var result: [UInt32: Rect] = [:]
        root?.frames(in: rect, gap: gap, into: &result)
        return result
    }

    mutating func insert(
        _ id: UInt32, beside target: UInt32?, direction: CardinalDirection? = nil, in rect: Rect, gap: CGFloat
    ) {
        guard !windowIds.contains(id) else { return }
        guard let existing = root else {
            root = .window(id)
            return
        }
        let target = target.flatMap { windowIds.contains($0) ? $0 : nil } ?? windowIds.last!
        let region = frames(in: rect, gap: gap)[target] ?? rect
        let axis = direction?.orientation ?? (region.width >= region.height ? .h : .v)
        let newFirst = direction.map { !$0.isPositive } ?? false
        let split = Node.split(axis, 0.5, .window(newFirst ? id : target), .window(newFirst ? target : id))
        root = existing.replacing(target, with: split)
    }

    mutating func remove(_ id: UInt32) { retain(Set(windowIds).subtracting([id])) }
    mutating func retain(_ ids: Set<UInt32>) { root = root?.retaining(ids) }

    mutating func move(_ id: UInt32, beside target: UInt32, direction: CardinalDirection, in rect: Rect, gap: CGFloat) {
        guard id != target, windowIds.contains(id), windowIds.contains(target) else { return }
        remove(id)
        insert(id, beside: target, direction: direction, in: rect, gap: gap)
    }

    mutating func swap(_ a: UInt32, _ b: UInt32) {
        guard windowIds.contains(a), windowIds.contains(b) else { return }
        root = root?.swapping(a, b)
    }

    mutating func merge(_ other: BinaryLayout, axis: Orientation) {
        precondition(Set(windowIds).isDisjoint(with: other.windowIds))
        guard let incoming = other.root else { return }
        root = root.map { .split(axis, 0.5, $0, incoming) } ?? incoming
    }

    mutating func balance() { root = root?.balanced() }

    @discardableResult
    mutating func toggleSplit(for id: UInt32, in rect: Rect, gap: CGFloat) -> Bool {
        editSplit(for: id, in: rect, gap: gap) { axis, ratio, _, _ in (axis.opposite, ratio) }
    }

    @discardableResult
    mutating func resize(_ id: UInt32, by points: CGFloat, in rect: Rect, gap: CGFloat) -> Bool {
        editSplit(for: id, in: rect, gap: gap) { axis, ratio, inFirst, region in
            let available = max(0, region.getDimension(axis) - gap)
            guard available > 0 else { return nil }
            return (axis, Self.clamp(ratio + (inFirst ? points : -points) / available))
        }
    }

    /// Move the nearest ancestor divider that forms this edge of the window.
    @discardableResult
    mutating func resizeEdge(_ id: UInt32, edge: CardinalDirection, by delta: CGFloat, in rect: Rect, gap: CGFloat)
        -> Bool
    {
        editSplit(for: id, in: rect, gap: gap) { axis, ratio, inFirst, region in
            guard axis == edge.orientation, inFirst == edge.isPositive else { return nil }
            let available = max(0, region.getDimension(axis) - gap)
            guard available > 0 else { return nil }
            return (axis, Self.clamp(ratio + delta / available))
        }
    }

    private mutating func editSplit(
        for id: UInt32, in rect: Rect, gap: CGFloat,
        edit: (Orientation, CGFloat, Bool, Rect) -> (Orientation, CGFloat)?
    ) -> Bool {
        guard let root else { return false }
        let (updated, changed) = root.editingSplit(for: id, in: rect, gap: gap, edit: edit)
        self.root = updated
        return changed
    }

    private static func clamp(_ ratio: CGFloat) -> CGFloat { min(0.9, max(0.1, ratio)) }

    private static func divide(_ rect: Rect, axis: Orientation, ratio: CGFloat, gap: CGFloat) -> (Rect, Rect) {
        let gap = min(max(0, gap), rect.getDimension(axis))
        let length = max(0, rect.getDimension(axis) - gap)
        var a = rect
        var b = rect
        if axis == .h {
            a.width = length * ratio
            b.topLeftX += a.width + gap
            b.width = length - a.width
        } else {
            a.height = length * ratio
            b.topLeftY += a.height + gap
            b.height = length - a.height
        }
        return (a, b)
    }
}
