import AppKit
import Common

/// Pure layout model. Direction belongs to depth; every branch has exactly two children.
struct BinaryLayout: Equatable {
    enum Placement: String { case outer, inner }
    private indirect enum Node: Equatable {
        case window(UInt32)
        case split(CGFloat, Node, Node)

        var ids: [UInt32] {
            switch self {
            case .window(let id): [id]
            case .split(_, let a, let b): a.ids + b.ids
            }
        }
        func retaining(_ ids: Set<UInt32>) -> Node? {
            switch self {
            case .window(let id): ids.contains(id) ? self : nil
            case .split(let ratio, let a, let b):
                switch (a.retaining(ids), b.retaining(ids)) {
                case (let a?, let b?): .split(ratio, a, b)
                case (let a?, nil): a
                case (nil, let b?): b
                case (nil, nil): nil
                }
            }
        }
        func replacing(_ id: UInt32, with replacement: Node) -> Node {
            switch self {
            case .window(let old): old == id ? replacement : self
            case .split(let ratio, let a, let b):
                .split(ratio, a.replacing(id, with: replacement), b.replacing(id, with: replacement))
            }
        }
        func mapped(_ transform: (UInt32) -> UInt32) -> Node {
            switch self {
            case .window(let id): .window(transform(id))
            case .split(let ratio, let a, let b): .split(ratio, a.mapped(transform), b.mapped(transform))
            }
        }
        func at(_ path: ArraySlice<Bool>) -> Node? {
            guard let first = path.first else { return self }
            guard case .split(_, let a, let b) = self else { return nil }
            return (first ? b : a).at(path.dropFirst())
        }
        func editing(_ path: ArraySlice<Bool>, _ edit: (Node) -> Node) -> Node {
            guard let first = path.first else { return edit(self) }
            guard case .split(let ratio, let a, let b) = self else { return self }
            return .split(
                ratio, first ? a : a.editing(path.dropFirst(), edit), first ? b.editing(path.dropFirst(), edit) : b)
        }
        func balanced() -> Node {
            switch self {
            case .window: self
            case .split(_, let a, let b): .split(0.5, a.balanced(), b.balanced())
            }
        }
    }

    struct Leaf {
        let id: UInt32
        let rect: Rect
        let path: [Bool]
    }
    struct Section {
        let rect: Rect
        let axis: Orientation
        let path: [Bool]
        let ids: [UInt32]
    }
    private var root: Node?
    var rootAxis: Orientation = .h
    var windowIds: [UInt32] { root?.ids ?? [] }
    static let baseline = CGSize(width: 320, height: 200)
    typealias Minimums = [UInt32: CGSize]

    private static func length(_ size: CGSize, _ axis: Orientation) -> CGFloat { axis == .h ? size.width : size.height }
    private static func size(_ primary: CGFloat, _ cross: CGFloat, _ axis: Orientation) -> CGSize {
        axis == .h ? CGSize(width: primary, height: cross) : CGSize(width: cross, height: primary)
    }
    private static func minimum(_ id: UInt32, _ minimums: Minimums) -> CGSize {
        let known = minimums[id] ?? baseline
        return CGSize(width: max(baseline.width, known.width), height: max(baseline.height, known.height))
    }
    private func axis(at depth: Int) -> Orientation { depth.isMultiple(of: 2) ? rootAxis : rootAxis.opposite }

    func geometry(in rect: Rect, gap: CGFloat) -> (leaves: [Leaf], sections: [Section]) {
        var leaves: [Leaf] = []
        var sections: [Section] = []
        func visit(_ node: Node, _ rect: Rect, _ path: [Bool]) {
            switch node {
            case .window(let id): leaves.append(Leaf(id: id, rect: rect, path: path))
            case .split(let ratio, let a, let b):
                let axis = axis(at: path.count)
                sections.append(Section(rect: rect, axis: axis, path: path, ids: node.ids))
                let (ar, br) = Self.divide(rect, axis: axis, ratio: ratio, gap: gap)
                visit(a, ar, path + [false])
                visit(b, br, path + [true])
            }
        }
        if let root { visit(root, rect, []) }
        return (leaves, sections)
    }
    func frames(in rect: Rect, gap: CGFloat) -> [UInt32: Rect] {
        Dictionary(uniqueKeysWithValues: geometry(in: rect, gap: gap).leaves.map { ($0.id, $0.rect) })
    }
    func parent(of id: UInt32, in rect: Rect, gap: CGFloat) -> Section? {
        let geometry = geometry(in: rect, gap: gap)
        guard let path = geometry.leaves.first(where: { $0.id == id })?.path, !path.isEmpty else { return nil }
        return geometry.sections.first { $0.path == path.dropLast() }
    }
    /// The immediate sibling's entire region, whether it contains one window or a subdivided section.
    func siblingRegion(of id: UInt32, in rect: Rect, gap: CGFloat) -> Rect? {
        let geometry = geometry(in: rect, gap: gap)
        guard let leaf = geometry.leaves.first(where: { $0.id == id }), !leaf.path.isEmpty else { return nil }
        var siblingPath = leaf.path
        siblingPath[siblingPath.count - 1].toggle()
        return geometry.sections.first { $0.path == siblingPath }?.rect
            ?? geometry.leaves.first { $0.path == siblingPath }?.rect
    }
    func isValid(in rect: Rect, gap: CGFloat, minimums: Minimums = [:]) -> Bool {
        geometry(in: rect, gap: gap).leaves.allSatisfy {
            let min = Self.minimum($0.id, minimums)
            return $0.rect.width + 0.001 >= min.width && $0.rect.height + 0.001 >= min.height
        }
    }

    /// Insertion is deliberately local. A failed 50/50 insertion changes nothing.
    @discardableResult mutating func insert(
        _ id: UInt32, beside target: UInt32?, placement: Placement = .outer,
        in rect: Rect, gap: CGFloat, minimums: Minimums = [:]
    ) -> Bool {
        guard !windowIds.contains(id) else { return false }
        let before = root
        if let root {
            let leaves = geometry(in: rect, gap: gap).leaves
            let target = leaves.first { $0.id == target } ?? leaves.last!
            let axis = axis(at: target.path.count)
            let outerFirst = target.rect.center.getProjection(axis) < rect.center.getProjection(axis)
            let first = placement == .outer ? outerFirst : !outerFirst
            self.root = root.replacing(
                target.id, with: .split(0.5, .window(first ? id : target.id), .window(first ? target.id : id)))
        } else {
            root = .window(id)
        }
        guard isValid(in: rect, gap: gap, minimums: minimums) else {
            root = before
            return false
        }
        return true
    }
    mutating func remove(_ id: UInt32) { retain(Set(windowIds).subtracting([id])) }
    mutating func retain(_ ids: Set<UInt32>) { root = root?.retaining(ids) }
    mutating func balance() { root = root?.balanced() }

    /// Flexible minimums are used by recovery; fixed-ratio bounds clamp a single divider.
    private func required(_ node: Node, _ depth: Int, _ gap: CGFloat, _ minimums: Minimums, fixed: Bool = false)
        -> CGSize
    {
        switch node {
        case .window(let id): return Self.minimum(id, minimums)
        case .split(let ratio, let a, let b):
            let axis = axis(at: depth)
            let x = required(a, depth + 1, gap, minimums, fixed: fixed)
            let y = required(b, depth + 1, gap, minimums, fixed: fixed)
            let primary =
                fixed
                ? max(Self.length(x, axis) / ratio, Self.length(y, axis) / (1 - ratio)) + gap
                : Self.length(x, axis) + Self.length(y, axis) + gap
            return Self.size(primary, max(Self.length(x, axis.opposite), Self.length(y, axis.opposite)), axis)
        }
    }
    private func fitted(_ node: Node, _ depth: Int, _ rect: Rect, _ gap: CGFloat, _ minimums: Minimums) -> Node? {
        let minSize = required(node, depth, gap, minimums)
        guard rect.width + 0.001 >= minSize.width, rect.height + 0.001 >= minSize.height else { return nil }
        guard case .split(let ratio, let a, let b) = node else { return node }
        let axis = axis(at: depth)
        let available = rect.getDimension(axis) - gap
        let lo = Self.length(required(a, depth + 1, gap, minimums), axis) / available
        let hi = 1 - Self.length(required(b, depth + 1, gap, minimums), axis) / available
        let fittedRatio = min(hi, max(lo, ratio))
        let (ar, br) = Self.divide(rect, axis: axis, ratio: fittedRatio, gap: gap)
        guard let a = fitted(a, depth + 1, ar, gap, minimums), let b = fitted(b, depth + 1, br, gap, minimums) else {
            return nil
        }
        return .split(fittedRatio, a, b)
    }
    /// After unavoidable topology/geometry changes, preserve ratios, then float oldest tiles.
    mutating func recover(in rect: Rect, gap: CGFloat, minimums: Minimums = [:], oldestFirst: [UInt32]) -> [UInt32] {
        var floated: [UInt32] = []
        while let root {
            if let fitted = fitted(root, 0, rect, gap, minimums) {
                self.root = fitted
                break
            }
            let id = oldestFirst.first { windowIds.contains($0) } ?? windowIds.first!
            remove(id)
            floated.append(id)
        }
        return floated
    }

    @discardableResult mutating func resize(
        _ id: UInt32, axis requested: Orientation? = nil, by points: CGFloat,
        in rect: Rect, gap: CGFloat, minimums: Minimums = [:]
    ) -> Bool {
        editDivider(id, axis: requested, edge: nil, delta: points, in: rect, gap: gap, minimums: minimums)
    }
    @discardableResult mutating func resizeEdge(
        _ id: UInt32, edge: CardinalDirection, by delta: CGFloat,
        in rect: Rect, gap: CGFloat, minimums: Minimums = [:]
    ) -> Bool {
        editDivider(id, axis: edge.orientation, edge: edge, delta: delta, in: rect, gap: gap, minimums: minimums)
    }
    private mutating func editDivider(
        _ id: UInt32, axis requested: Orientation?, edge: CardinalDirection?, delta: CGFloat,
        in rect: Rect, gap: CGFloat, minimums: Minimums
    ) -> Bool {
        let geometry = geometry(in: rect, gap: gap)
        guard let leaf = geometry.leaves.first(where: { $0.id == id }) else { return false }
        for depth in leaf.path.indices.reversed() {
            let path = Array(leaf.path.prefix(depth))
            let axis = axis(at: depth)
            let inFirst = !leaf.path[depth]
            guard requested == nil || requested == axis, edge == nil || inFirst == edge?.isPositive else { continue }
            guard let section = geometry.sections.first(where: { $0.path == path }),
                case .split(let ratio, let a, let b) = root?.at(path[...])
            else { return false }
            let available = section.rect.getDimension(axis) - gap
            let lo = Self.length(required(a, depth + 1, gap, minimums, fixed: true), axis) / available
            let hi = 1 - Self.length(required(b, depth + 1, gap, minimums, fixed: true), axis) / available
            guard available > 0, lo <= hi else { return false }
            let change = edge == nil && !inFirst ? -delta : delta
            let fittedRatio = min(hi, max(lo, ratio + change / available))
            root = root?.editing(path[...]) { _ in .split(fittedRatio, a, b) }
            return true
        }
        return false
    }

    /// The selected dimension is an exact constraint; sibling subtrees remain flexible.
    private func preserving(
        _ id: UInt32, axis moveAxis: Orientation, length: CGFloat, in rect: Rect, gap: CGFloat, minimums: Minimums
    ) -> Node? {
        struct Bounds {
            let min: CGFloat
            let max: CGFloat
            let cross: CGFloat
        }
        func bounds(_ node: Node, _ depth: Int) -> Bounds {
            if !node.ids.contains(id) {
                let min = required(node, depth, gap, minimums)
                return Bounds(
                    min: Self.length(min, moveAxis), max: .infinity, cross: Self.length(min, moveAxis.opposite))
            }
            switch node {
            case .window(let id):
                return Bounds(
                    min: length, max: length, cross: Self.length(Self.minimum(id, minimums), moveAxis.opposite))
            case .split(_, let a, let b):
                let a = bounds(a, depth + 1)
                let b = bounds(b, depth + 1)
                if axis(at: depth) == moveAxis {
                    return Bounds(min: a.min + b.min + gap, max: a.max + b.max + gap, cross: max(a.cross, b.cross))
                }
                return Bounds(min: max(a.min, b.min), max: min(a.max, b.max), cross: a.cross + b.cross + gap)
            }
        }
        func arrange(_ node: Node, _ depth: Int, _ rect: Rect) -> Node? {
            let limits = bounds(node, depth)
            let length = rect.getDimension(moveAxis)
            guard length + 0.001 >= limits.min, length <= limits.max + 0.001,
                rect.getDimension(moveAxis.opposite) + 0.001 >= limits.cross
            else { return nil }
            if !node.ids.contains(id) { return fitted(node, depth, rect, gap, minimums) }
            guard case .split(let ratio, let a, let b) = node else { return node }
            let axis = axis(at: depth)
            let available = rect.getDimension(axis) - gap
            let x = bounds(a, depth + 1)
            let y = bounds(b, depth + 1)
            let lo = axis == moveAxis ? max(x.min, available - y.max) : x.cross
            let hi = axis == moveAxis ? min(x.max, available - y.min) : available - y.cross
            guard lo <= hi + 0.001, available > 0 else { return nil }
            let fittedRatio = min(hi, max(lo, ratio * available)) / available
            let (ar, br) = Self.divide(rect, axis: axis, ratio: fittedRatio, gap: gap)
            guard let a = arrange(a, depth + 1, ar), let b = arrange(b, depth + 1, br) else { return nil }
            return .split(fittedRatio, a, b)
        }
        return root.flatMap { arrange($0, 0, rect) }
    }

    @discardableResult mutating func swap(
        _ id: UInt32, with other: UInt32, section: Bool = false, axis requested: Orientation? = nil,
        in rect: Rect, gap: CGFloat, minimums: Minimums = [:]
    ) -> Bool {
        let leaves = geometry(in: rect, gap: gap).leaves
        guard id != other, let source = leaves.first(where: { $0.id == id }),
            let target = leaves.first(where: { $0.id == other }), let before = root
        else { return false }
        let depth = zip(source.path, target.path).prefix { $0 == $1 }.count
        let moveAxis = requested ?? axis(at: depth)
        if section {
            guard !source.path.isEmpty, source.path.dropLast() == target.path.prefix(source.path.count - 1),
                source.path.last != target.path[source.path.count - 1]
            else { return false }
            root = before.editing(source.path.dropLast()) {
                guard case .split(let ratio, let a, let b) = $0 else { return $0 }
                return .split(ratio, b, a)
            }
        } else {
            root = before.mapped { $0 == id ? other : $0 == other ? id : $0 }
        }
        if let fitted = preserving(
            id, axis: moveAxis, length: source.rect.getDimension(moveAxis), in: rect, gap: gap, minimums: minimums)
        {
            root = fitted
            if isValid(in: rect, gap: gap, minimums: minimums) { return true }
        }
        root = before
        return false
    }

    @discardableResult mutating func move(
        _ id: UInt32, direction: CardinalDirection, in rect: Rect, gap: CGFloat, minimums: Minimums = [:],
        windowOnly: Bool = false
    ) -> Bool {
        let geometry = geometry(in: rect, gap: gap)
        guard let source = geometry.leaves.first(where: { $0.id == id }), !source.path.isEmpty,
            let parent = parent(of: id, in: rect, gap: gap)
        else { return false }
        if !windowOnly, parent.axis == direction.orientation, source.path.last == !direction.isPositive,
            let sibling = parent.ids.first(where: { $0 != id })
        {
            return swap(
                id, with: sibling, section: true, axis: direction.orientation, in: rect, gap: gap, minimums: minimums)
        }
        let frames = Dictionary(
            uniqueKeysWithValues: geometry.leaves.filter {
                $0.id == id || windowOnly || !parent.ids.contains($0.id)
            }.map { ($0.id, $0.rect) })
        guard let other = directionalNeighbor(of: id, direction: direction, frames: frames) else { return false }
        return swap(id, with: other, axis: direction.orientation, in: rect, gap: gap, minimums: minimums)
    }

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
