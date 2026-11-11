import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct StateMachineFuzzTest {
        init() { setUpWorkspacesForTests() }

        @Test func seededLifecyclePointerAndCommandSequencesPreserveAllInvariants() async throws {
            for seed: UInt64 in 1...25 {
                setUpWorkspacesForTests()
                var rng = SplitMix64(seed: seed)
                let pointer = TestPointerAdapter()
                let baseMonitors: [MonitorInfo] = [
                    TestMonitor(displayId: "m1", name: "Main", x: 0, y: 0, isMain: true, width: 1440, height: 900),
                    TestMonitor(displayId: "m2", name: "Right", x: 1440, y: 0, width: 1280, height: 1024),
                ]
                unsafe testMonitors = baseMonitors
                let state = DisplayLayoutState(monitors: baseMonitors, pointer: pointer)
                DisplayLayoutState.shared = state
                let desktop = TestDesktopSessionAdapter()
                let execution = ActionExecution(desktop: desktop)
                ActionExecution.shared = execution
                defer { execution.cancelRefresh() }

                var nextId: UInt32 = 1
                var lockedIds: [(id: UInt32, wasMinimized: Bool, wasFullscreen: Bool?)] = []

                for step in 0..<60 {
                    let choice = Int.random(in: 0..<12, using: &rng)
                    switch choice {
                    case 0, 1:
                        // Create a window of varied kind/resizability/deferred availability.
                        guard state.allWindows.count < 9 else { break }
                        let id = nextId
                        nextId += 1
                        let kinds: [WindowKind] = [.tiled, .tiled, .tiled, .floating, .popup, .minimized, .hidden]
                        let kind = kinds[Int.random(in: 0..<kinds.count, using: &rng)]
                        let workspace = state.focus.workspace
                        let rect = Rect(topLeftX: 120, topLeftY: 100, width: 420, height: 300)
                        let w = TestWindow.new(id: id, workspace: workspace, kind: kind, rect: rect)
                        if Bool.random(using: &rng) && kind == .floating {
                            w.isResizable = false
                        }
                        if kind == .minimized {
                            w.isMacosMinimizedForTest = true
                            if Bool.random(using: &rng) {
                                w.needsClassificationOnResume = true
                                w.resumeClassificationForTest = (
                                    Bool.random(using: &rng) ? .tiled : .floating,
                                    Bool.random(using: &rng)
                                )
                            }
                        } else if kind == .hidden {
                            w.needsClassificationOnResume = true
                            w.resumeClassificationForTest = (.tiled, true)
                        }
                        if w.isFocusable, Bool.random(using: &rng) {
                            _ = w.focusWindow()
                            desktop.nativeFocus = w
                        }

                    case 2:
                        // Close a random window.
                        if let target = state.allWindows.randomElement(using: &rng) {
                            state.removeWindow(target, remember: Bool.random(using: &rng))
                            if desktop.nativeFocus === target {
                                desktop.nativeFocus = state.focus.windowOrNil
                            }
                        }

                    case 3:
                        // Toggle native minimize / fullscreen / app hidden and run refresh reconciliation.
                        if let target = state.allWindows.compactMap({ $0 as? TestWindow }).randomElement(using: &rng),
                            target.kind != .popup
                        {
                            switch Int.random(in: 0..<3, using: &rng) {
                            case 0:
                                target.isMacosMinimizedForTest.toggle()
                                if target.isMacosMinimizedForTest { target.isMacosFullscreenForTest = false }
                            case 1:
                                let states: [Bool?] = [false, true, nil]
                                target.isMacosFullscreenForTest = states[Int.random(in: 0..<states.count, using: &rng)]
                                if target.isMacosFullscreenForTest == true { target.isMacosMinimizedForTest = false }
                            default:
                                TestApp.shared.isHidden.toggle()
                            }
                        }
                        desktop.nativeFocus = state.focus.windowOrNil
                        await execution.refresh(.startup, assumeCancellable: false)

                    case 4:
                        // Transient observation loss (lock screen) and out-of-order restoration.
                        if lockedIds.isEmpty {
                            let candidates = state.allWindows.compactMap { $0 as? TestWindow }.filter {
                                $0.kind != .popup
                            }
                            guard !candidates.isEmpty else { break }
                            lockedIds = candidates.map {
                                ($0.windowId, $0.isMacosMinimizedForTest, $0.isMacosFullscreenForTest)
                            }
                            for window in candidates {
                                state.removeWindow(window, remember: true)
                            }
                        } else {
                            lockedIds.shuffle(using: &rng)
                            for entry in lockedIds where state.window(for: entry.id) == nil {
                                let w = TestWindow.new(
                                    id: entry.id, workspace: state.mainWorkspace,
                                    rect: Rect(topLeftX: 80, topLeftY: 80, width: 400, height: 300))
                                w.isMacosMinimizedForTest = entry.wasMinimized
                                w.isMacosFullscreenForTest = entry.wasFullscreen
                                _ = state.restoreWindow(newlyDetectedWindow: w)
                            }
                            lockedIds.removeAll()
                        }

                    case 5, 6:
                        // Execute a model/user action.
                        let actions: [Action] = [
                            .focusLeft, .focusRight, .focusUp, .focusDown,
                            .moveLeft, .moveRight, .moveUp, .moveDown,
                            .grow, .shrink, .balanceSizes,
                            .toggleFloating, .toggleOrientation, .fullscreen,
                            .leftMonitor, .rightMonitor, .upMonitor, .downMonitor,
                            .nextMonitor, .previousMonitor,
                            .moveToMonitorLeft, .moveToMonitorRight, .moveToMonitorUp, .moveToMonitorDown,
                            .moveToNextMonitor, .moveToPreviousMonitor,
                        ]
                        let action = actions[Int.random(in: 0..<actions.count, using: &rng)]
                        desktop.nativeFocus = state.focus.windowOrNil
                        _ = try await execution.execute(action)
                        execution.cancelRefresh()

                    case 7, 8:
                        // Pointer gesture: drag swap, cross-screen preview/drop, edge resize, cancel, or missed release.
                        let focusable = state.allWindows.filter { $0.kind == .tiled || $0.kind == .floating }
                        guard let window = focusable.randomElement(using: &rng),
                            let source = window.workspace
                        else { break }
                        pointer.isButtonDown = true
                        let base =
                            window.gestureBaselineRect
                            ?? source.tiledFrames[window.windowId]
                            ?? Rect(topLeftX: 100, topLeftY: 100, width: 400, height: 300)
                        var sample = base
                        if Bool.random(using: &rng) {
                            sample.topLeftX += CGFloat(Int.random(in: -60...60, using: &rng))
                            sample.topLeftY += CGFloat(Int.random(in: -40...40, using: &rng))
                        } else {
                            let delta = CGFloat(Int.random(in: -80...80, using: &rng))
                            sample.width = max(120, sample.width + delta)
                        }
                        let destination = state.workspaces.randomElement(using: &rng) ?? source
                        let targetPoint: CGPoint
                        if let other = destination.tiledFrames.values.randomElement(using: &rng) {
                            targetPoint = other.center
                        } else {
                            targetPoint = destination.layoutRect.center
                        }
                        state.updatePointer(window, frame: sample, at: targetPoint, on: destination)
                        switch Int.random(in: 0..<4, using: &rng) {
                        case 0:
                            pointer.isButtonDown = false
                            state.finishPointer(at: targetPoint, on: destination)
                        case 1:
                            state.cancelPointer()
                            if Bool.random(using: &rng) {
                                pointer.isButtonDown = false
                                state.reconcileReleasedPointer()
                            }
                        case 2:
                            state.resetMissedPointerRelease()
                        default:
                            break  // Leave gesture active across the next lifecycle step!
                        }

                    case 9:
                        // Monitor geometry / topology change (1-3 displays, including vertical stacks and shrinks).
                        let variant = Int.random(in: 0..<5, using: &rng)
                        let nextMonitors: [MonitorInfo]
                        switch variant {
                        case 0:
                            nextMonitors = [
                                TestMonitor(
                                    displayId: "m1", name: "Small", x: 0, y: 0, isMain: true, width: 520, height: 340)
                            ]
                        case 1:
                            nextMonitors = baseMonitors
                        case 2:
                            nextMonitors =
                                baseMonitors + [
                                    TestMonitor(
                                        displayId: "m3", name: "Top", x: 300, y: -1080, width: 1920, height: 1080)
                                ]
                        case 3:
                            nextMonitors = [
                                TestMonitor(
                                    displayId: "m1", name: "Portrait", x: 0, y: 0, isMain: true,
                                    width: 900, height: 1440),
                                TestMonitor(displayId: "m2", name: "Bottom", x: 200, y: 1440, width: 1600, height: 900),
                            ]
                        default:
                            nextMonitors = []  // Transient empty display list
                        }
                        if !nextMonitors.isEmpty { unsafe testMonitors = nextMonitors }
                        state.reconcileMonitors(nextMonitors)

                    case 10:
                        // Cell-snapping or application minimum-size feedback + layout pass.
                        for ws in state.workspaces {
                            try await ws.layoutWorkspace()
                        }
                        if let tiled = state.allWindows.filter({ $0.kind == .tiled }).randomElement(using: &rng),
                            let applied = tiled.lastAppliedLayoutPhysicalRect
                        {
                            if Bool.random(using: &rng) {
                                let rounded = CGSize(
                                    width: max(160, applied.width - 8),
                                    height: max(100, applied.height - 6))
                                _ = tiled.observeAppliedSize(requested: applied.size, actual: rounded)
                            } else {
                                let constrained = CGSize(width: applied.width + 60, height: applied.height + 40)
                                _ = tiled.observeAppliedSize(requested: applied.size, actual: constrained)
                                tiled.lastAppliedLayoutPhysicalRect = applied
                                if tiled.observeAppliedSize(requested: applied.size, actual: constrained) {
                                    tiled.workspace?.recover()
                                }
                            }
                        }

                    default:
                        // Placement / gap config toggle.
                        let placement = Bool.random(using: &rng) ? "outer" : "inner"
                        let gap = [0, 8, 12][Int.random(in: 0..<3, using: &rng)]
                        #expect(
                            ConfigurationApplication.shared.apply(
                                "gap = \(gap)\nnew-window-placement = '\(placement)'"
                            ).isOk)
                        state.reconcileMonitors(monitorInfos)
                    }

                    assertInvariants(state, seed: seed, step: step)
                }
                pointer.isButtonDown = false
                state.resetMissedPointerRelease()
                assertInvariants(state, seed: seed, step: 999)
            }
        }

        private func assertInvariants(_ state: DisplayLayoutState, seed: UInt64, step: Int) {
            let context = "seed=\(seed) step=\(step)"
            let report = state.diagnosticReport
            #expect(!report.contains("Membership inconsistency"), Comment(rawValue: "\(context)\n\(report)"))

            for workspace in state.workspaces {
                let ids = workspace.layout.windowIds
                #expect(Set(ids).count == ids.count, Comment(rawValue: context))
                let tiledOnWorkspace = Set(workspace.windows.filter { $0.kind == .tiled }.map(\.windowId))
                #expect(Set(ids) == tiledOnWorkspace, Comment(rawValue: context))
                #expect(
                    workspace.layout.isValid(
                        in: workspace.layoutRect, gap: CGFloat(config.gap), minimums: workspace.minimums),
                    Comment(rawValue: context))

                let bounds = workspace.layoutRect
                let rects = Array(workspace.tiledFrames.values)
                for (index, rect) in rects.enumerated() {
                    #expect(
                        rect.minX + 0.01 >= bounds.minX && rect.maxX - 0.01 <= bounds.maxX, Comment(rawValue: context))
                    #expect(
                        rect.minY + 0.01 >= bounds.minY && rect.maxY - 0.01 <= bounds.maxY, Comment(rawValue: context))
                    for other in rects.dropFirst(index + 1) {
                        let overlapsX = min(rect.maxX, other.maxX) - max(rect.minX, other.minX) > 0.01
                        let overlapsY = min(rect.maxY, other.maxY) - max(rect.minY, other.minY) > 0.01
                        #expect(!(overlapsX && overlapsY), Comment(rawValue: context))
                    }
                }
            }

            for window in state.allWindows {
                #expect(window.isRegistered, Comment(rawValue: context))
                let ws = window.workspace
                #expect(ws != nil && state.contains(ws!), Comment(rawValue: context))
                if !window.isResizable {
                    #expect(window.kind != .tiled, Comment(rawValue: context))
                }
            }

            let liveFocus = state.focus
            #expect(state.contains(liveFocus.workspace), Comment(rawValue: context))
            if let focused = liveFocus.windowOrNil {
                #expect(
                    focused.isRegistered && focused.isFocusable && focused.workspace === liveFocus.workspace,
                    Comment(rawValue: context))
            } else {
                #expect(liveFocus.workspace.isEffectivelyEmpty, Comment(rawValue: context))
            }

            if !state.isHandlingPointer {
                #expect(state.manipulatedWindow == nil && state.pointerPreview == nil, Comment(rawValue: context))
            }
            if let preview = state.pointerPreview {
                #expect(state.contains(preview.workspace), Comment(rawValue: context))
            }
        }
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
