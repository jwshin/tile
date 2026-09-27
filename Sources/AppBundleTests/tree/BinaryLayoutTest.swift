import AppKit
import Common
import Testing

@testable import AppBundle

struct BinaryLayoutTest {
    private let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1200, height: 800)

    @Test func insertionSplitsOnlyTheTargetAndRemovalPromotesSibling() throws {
        var layout = BinaryLayout()
        layout.insert(1, beside: nil, in: rect, gap: 0)
        layout.insert(2, beside: 1, in: rect, gap: 0)
        layout.insert(3, beside: 2, in: rect, gap: 0)
        let frames = layout.frames(in: rect, gap: 0)
        #expect(frames[1]?.size == CGSize(width: 600, height: 800))
        #expect(frames[2]?.size == CGSize(width: 600, height: 400))
        #expect(frames[3]?.topLeftCorner == CGPoint(x: 600, y: 400))
        layout.remove(2)
        #expect(layout.frames(in: rect, gap: 0)[3]?.size == CGSize(width: 600, height: 800))
        layout.remove(1)
        #expect(layout.frames(in: rect, gap: 0)[3]?.size == rect.size)
        layout.remove(3)
        #expect(layout.windowIds.isEmpty)
    }

    @Test func orientationAndRatiosSurviveGeometryChanges() {
        var layout = BinaryLayout()
        layout.insert(1, beside: nil, in: rect, gap: 0)
        layout.insert(2, beside: 1, in: rect, gap: 0)
        let changed29 = layout.resize(1, by: 120, in: rect, gap: 0)
        #expect(changed29)
        let portrait = Rect(topLeftX: 100, topLeftY: 50, width: 600, height: 1400)
        let frames = layout.frames(in: portrait, gap: 0)
        #expect(frames[1]?.width == 360)
        #expect(frames[2]?.width == 240)
        #expect(frames[2]?.minX == 460)
        #expect(frames[1]?.height == 1400)
    }

    @Test func sameAxisSplitsArePreservedAndToggleIsLocal() {
        var layout = BinaryLayout()
        for id: UInt32 in 1...3 { layout.insert(id, beside: id - 1, direction: .right, in: rect, gap: 0) }
        #expect(layout.frames(in: rect, gap: 0)[3]?.height == 800)
        let changed42 = layout.toggleSplit(for: 3, in: rect, gap: 0)
        #expect(changed42)
        #expect(layout.frames(in: rect, gap: 0)[1]?.size == CGSize(width: 600, height: 800))
        #expect(layout.frames(in: rect, gap: 0)[3]?.size == CGSize(width: 600, height: 400))
    }

    @Test func movingAndSwappingDoNotLoseOrDuplicateWindows() {
        var layout = BinaryLayout()
        for id: UInt32 in 1...4 { layout.insert(id, beside: id - 1, in: rect, gap: 8) }
        layout.move(1, beside: 4, direction: .down, in: rect, gap: 8)
        let frames = layout.frames(in: rect, gap: 8)
        #expect(frames[1]!.minY == frames[4]!.maxY + 8)
        layout.swap(1, 4)
        #expect(layout.frames(in: rect, gap: 8)[1]?.topLeftCorner == frames[4]?.topLeftCorner)
        layout.insert(1, beside: 3, in: rect, gap: 8)
        layout.move(3, beside: 99, direction: .left, in: rect, gap: 8)
        #expect(Set(layout.windowIds) == Set([1, 2, 3, 4]))
        #expect(layout.windowIds.count == 4)
    }

    @Test func balanceUsesLeafCountsRatherThanHalfAtEverySplit() {
        var layout = BinaryLayout()
        for id: UInt32 in 1...3 { layout.insert(id, beside: id - 1, direction: .right, in: rect, gap: 0) }
        layout.balance()
        let frames = layout.frames(in: rect, gap: 0)
        for id: UInt32 in 1...3 { #expect(abs(frames[id]!.width - 400) < 0.001) }
    }

    @Test func resizingAnOuterEdgeDoesNothingAndInnerEdgeFindsAncestor() {
        var layout = BinaryLayout()
        for id: UInt32 in 1...3 { layout.insert(id, beside: id - 1, in: rect, gap: 0) }
        let before = layout
        let changed73 = !layout.resizeEdge(3, edge: .right, by: 40, in: rect, gap: 0)
        #expect(changed73)
        #expect(layout == before)
        let changed75 = layout.resizeEdge(3, edge: .left, by: -100, in: rect, gap: 0)
        #expect(changed75)
        #expect(layout.frames(in: rect, gap: 0)[1]?.width == 500)
        #expect(layout.frames(in: rect, gap: 0)[2]?.width == 700)
        let changed78 = layout.resize(3, by: 100000, in: rect, gap: 0)
        #expect(changed78)
        #expect(layout.frames(in: rect, gap: 0).values.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    @Test func snapshotsAreValuesAndMissingLeavesCollapseWithoutMutatingSnapshot() {
        var layout = BinaryLayout()
        for id: UInt32 in 1...4 { layout.insert(id, beside: id - 1, in: rect, gap: 0) }
        let snapshot = layout
        layout.retain([2, 4])
        #expect(layout.windowIds == [2, 4])
        #expect(snapshot.windowIds == [1, 2, 3, 4])
    }

    @Test func gapsAndTinyRegionsNeverProduceNegativeFrames() {
        var layout = BinaryLayout()
        for id: UInt32 in 1...8 { layout.insert(id, beside: id - 1, in: rect, gap: 8) }
        let tiny = Rect(topLeftX: -100, topLeftY: 0, width: 2, height: 3)
        for frame in layout.frames(in: tiny, gap: 1000).values {
            #expect(frame.width >= 0 && frame.height >= 0)
            #expect(frame.minX >= tiny.minX && frame.maxX <= tiny.maxX)
            #expect(frame.minY >= tiny.minY && frame.maxY <= tiny.maxY)
        }
    }

    @Test func deterministicEditSequencePreservesCoverageAndIdentity() {
        var layout = BinaryLayout()
        for id: UInt32 in 1...24 {
            layout.insert(id, beside: id > 1 ? (id / 2) : nil, in: rect, gap: 0)
        }
        for id: UInt32 in 1...24 {
            layout.move(id, beside: id == 24 ? 1 : id + 1, direction: id % 2 == 0 ? .left : .down, in: rect, gap: 0)
            layout.resize(id, by: 37, in: rect, gap: 0)
            let frames = layout.frames(in: rect, gap: 0)
            #expect(frames.count == 24)
            let area = frames.values.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
            #expect(abs(area - rect.width * rect.height) < 0.001)
            #expect(Set(layout.windowIds).count == layout.windowIds.count)
        }
        for id: UInt32 in 1...24 { layout.remove(id) }
        #expect(layout.windowIds.isEmpty)
    }
}
