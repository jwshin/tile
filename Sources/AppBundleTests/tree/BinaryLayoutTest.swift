import AppKit
import Common
import Testing

@testable import AppBundle

struct BinaryLayoutTest {
    private let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1440, height: 900)
    private func three(_ rect: Rect, axis: Orientation = .h, gap: CGFloat = 0) -> BinaryLayout {
        var layout = BinaryLayout(rootAxis: axis)
        for id: UInt32 in 1...3 { layout.insert(id, beside: id - 1, in: rect, gap: gap) }
        return layout
    }

    @Test func alternationFollowsDepthEvenWhenTargetShapeWouldSuggestAnotherAxis() {
        let wide = Rect(topLeftX: 0, topLeftY: 0, width: 3200, height: 900)
        var layout = three(wide)
        let frames = layout.frames(in: wide, gap: 0)
        #expect(frames[2]?.size == CGSize(width: 1600, height: 450))
        layout.remove(1)
        let promoted = layout.frames(in: wide, gap: 0)
        #expect(promoted[2]?.size == CGSize(width: 1600, height: 900))
        #expect(promoted[3]?.minX == 1600)
        layout.remove(2)
        #expect(layout.frames(in: wide, gap: 0)[3]?.size == wide.size)
        layout.remove(3)
        #expect(layout.windowIds.isEmpty)
    }

    @Test func outerInnerUsesScreenCenterOnBothAxes() {
        for axis in [Orientation.h, .v] {
            let bounds = Rect(topLeftX: -1500, topLeftY: 100, width: 1600, height: 1600)
            for placement in [BinaryLayout.Placement.outer, .inner] {
                for side: UInt32 in [1, 2] {
                    var layout = BinaryLayout(rootAxis: axis)
                    layout.insert(1, beside: nil, in: bounds, gap: 12)
                    layout.insert(2, beside: 1, in: bounds, gap: 12)
                    layout.insert(3, beside: side, in: bounds, gap: 12)
                    let accepted38 = layout.insert(4, beside: side, placement: placement, in: bounds, gap: 12)
                    #expect(accepted38)
                    let frames = layout.frames(in: bounds, gap: 12)
                    let before = frames[4]!.center.getProjection(axis) < frames[side]!.center.getProjection(axis)
                    #expect(before == (placement == .outer ? side == 1 : side == 2))
                }
            }
        }
    }

    @Test func resizedMovesCarryWideAndNarrowAllocations() {
        for axis in [Orientation.h, .v] {
            let bounds = Rect(topLeftX: 0, topLeftY: 0, width: 1800, height: 1800)
            for selected: UInt32 in [1, 3] {
                var layout = three(bounds, axis: axis, gap: 12)
                layout.resize(1, axis: axis, by: (1800 - 12) * 0.2, in: bounds, gap: 12)
                let before = layout.frames(in: bounds, gap: 12)
                let direction: CardinalDirection =
                    axis == .h ? (selected == 1 ? .right : .left) : (selected == 1 ? .down : .up)
                let accepted55 = layout.move(selected, direction: direction, in: bounds, gap: 12)
                #expect(accepted55)
                let after = layout.frames(in: bounds, gap: 12)
                #expect(abs(after[selected]!.getDimension(axis) - before[selected]!.getDimension(axis)) < 0.001)
                #expect(layout.isValid(in: bounds, gap: 12))
                #expect(layout.windowIds == (selected == 1 ? [2, 3, 1] : [3, 2, 1]))
            }
        }
    }

    @Test func nestedSwapRedistributesAncestorAndLocalDividers() {
        let bounds = Rect(topLeftX: 0, topLeftY: 0, width: 2400, height: 1200)
        var layout = three(bounds, gap: 12)
        layout.insert(4, beside: 3, in: bounds, gap: 12)
        layout.resize(1, axis: .h, by: 240, in: bounds, gap: 12)
        let width = layout.frames(in: bounds, gap: 12)[1]!.width
        let accepted70 = layout.swap(1, with: 3, in: bounds, gap: 12)
        #expect(accepted70)
        #expect(abs(layout.frames(in: bounds, gap: 12)[1]!.width - width) < 0.001)
        #expect(layout.isValid(in: bounds, gap: 12))
        let accepted73 = layout.swap(1, with: 3, in: bounds, gap: 12)
        #expect(accepted73)
        #expect(abs(layout.frames(in: bounds, gap: 12)[1]!.width - width) < 0.001)
    }

    @Test func infeasibleSwapIsAtomicAndDoesNotFloatOrShrinkSelectedWindow() {
        var layout = BinaryLayout()
        layout.insert(1, beside: nil, in: rect, gap: 0)
        layout.insert(2, beside: 1, in: rect, gap: 0)
        layout.insert(3, beside: 1, in: rect, gap: 0)
        layout.resize(1, axis: .h, by: 240, in: rect, gap: 0)
        let minimums: BinaryLayout.Minimums = [3: CGSize(width: 800, height: 200)]
        #expect(layout.isValid(in: rect, gap: 0, minimums: minimums))
        // W3 needs the wide left column too. Moving W1 alone cannot shrink W3's column enough.
        let before = layout
        let moved = layout.swap(1, with: 2, in: rect, gap: 0, minimums: minimums)
        #expect(!moved)
        #expect(layout == before)
    }

    @Test func insertionDoesNotResizeExistingSectionsToFitAndKnownMinimumWins() {
        var layout = three(rect)
        let before = layout
        let accepted91 = !layout.insert(4, beside: 3, in: rect, gap: 0, minimums: [4: CGSize(width: 500, height: 200)])
        #expect(accepted91)
        #expect(layout == before)
        let accepted93 = !layout.insert(1, beside: 3, in: rect, gap: 0)
        #expect(accepted93)
        var empty = BinaryLayout()
        let accepted95 = !empty.insert(
            1, beside: nil, in: Rect(topLeftX: 0, topLeftY: 0, width: 300, height: 900), gap: 0)
        #expect(accepted95)
        #expect(empty.windowIds.isEmpty)
    }

    @Test func resizeClampsAtApplicationMinimumAndFindsNearestAxis() {
        var layout = three(rect, gap: 12)
        let before = layout.frames(in: rect, gap: 12)
        let accepted102 = layout.resize(
            3, axis: .h, by: 10000, in: rect, gap: 12, minimums: [1: CGSize(width: 500, height: 200)])
        #expect(accepted102)
        let wider = layout.frames(in: rect, gap: 12)
        #expect(abs(wider[1]!.width - 500) < 0.001)
        #expect(wider[2]!.width == wider[3]!.width)
        #expect(wider[3]!.height == before[3]!.height)
        let accepted107 = layout.resize(3, axis: .v, by: 10000, in: rect, gap: 12)
        #expect(accepted107)
        #expect(abs(layout.frames(in: rect, gap: 12)[2]!.height - 200) < 0.001)
        let unchanged = layout
        let accepted110 = !layout.resizeEdge(3, edge: .right, by: 50, in: rect, gap: 12)
        #expect(accepted110)
        #expect(layout == unchanged)
    }

    @Test func collapseRotatesAndRecoveryFloatsLeastRecentOnlyWhenRequired() {
        var layout = three(rect)
        layout.insert(4, beside: 3, in: rect, gap: 0)
        layout.remove(1)
        let bounds = Rect(topLeftX: 0, topLeftY: 0, width: 660, height: 410)
        let accepted119 = layout.recover(in: bounds, gap: 12, oldestFirst: [4, 2, 3]) == [4]
        #expect(accepted119)
        #expect(layout.windowIds == [2, 3])
        #expect(layout.isValid(in: bounds, gap: 12))
    }

    @Test func snapshotAndMixedEditsKeepIdentityCoverageAndMinimums() {
        let bounds = Rect(topLeftX: -3200, topLeftY: -100, width: 3200, height: 2000)
        var layout = BinaryLayout()
        for id: UInt32 in 1...12 { layout.insert(id, beside: id / 2, in: bounds, gap: 0) }
        let snapshot = layout
        let ids = layout.windowIds
        for iteration in 0..<50 {
            let id = ids[iteration % ids.count]
            layout.move(id, direction: [.left, .right, .up, .down][iteration % 4], in: bounds, gap: 0)
            layout.resize(id, axis: iteration % 2 == 0 ? .h : .v, by: 37, in: bounds, gap: 0)
            #expect(Set(layout.windowIds) == Set(ids))
            #expect(layout.windowIds.count == ids.count)
            #expect(layout.isValid(in: bounds, gap: 0))
            let area = layout.frames(in: bounds, gap: 0).values.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
            #expect(abs(area - bounds.width * bounds.height) < 0.001)
        }
        layout.retain([2, 4])
        #expect(snapshot.windowIds == ids)
        #expect(layout.windowIds.allSatisfy { $0 == 2 || $0 == 4 })
    }
}
