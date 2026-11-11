import AppKit
import Common
import JavaScriptCore
import Testing

@testable import AppBundle

extension CoreTests {
    @MainActor struct PrototypeDifferentialTest {
        init() { setUpWorkspacesForTests() }

        @Test func targetedEdgeCasesMatchPrototypeModel() async throws {
            let harness = try DifferentialHarness()
            try harness.assertMatches("initial seed")

            // Centered tie rule with inner vs outer placement, unequal 70/30 section + window swaps,
            // infeasible minimum-size swap rejection, and shrink recovery order.
            try harness.applyPlacement(.inner)
            _ = try harness.createWindow(kind: .normal)  // W4
            try harness.resizeFocused(axis: .h, ratioDelta: 0.2)
            try harness.moveFocused(.left)
            try harness.moveFocused(.right)
            try harness.applyConstraint(id: 2, minWidth: 900, minHeight: 200)
            try harness.moveFocused(.up)
            try harness.applyConstraint(id: 2, minWidth: 200, minHeight: 140)

            // Explicit orientation + portrait geometry + cross-screen transfer + disconnect & empty reconnect.
            try harness.updateScreen(id: "B", x: 1480, y: 0, width: 900, height: 1440, orientation: nil)
            try harness.transferFocused(to: "B")
            _ = try harness.createWindow(kind: .normal)  // W5 on B
            _ = try harness.createWindow(kind: .dialog)  // W6 floating on B
            _ = try harness.createWindow(kind: .fixed)  // W7 fixed floating on B
            try harness.toggleFloatFocused()  // W7 stays floating (non-resizable)
            try harness.focusWindow(id: 6)
            try harness.toggleFloatFocused()  // W6 retiles on B
            try await harness.focusDirection(.left)
            try harness.disconnect(displayId: "B")
            try harness.reconnect(displayId: "B")
        }

        @Test func seededOperationTracesMatchPrototypeModel() async throws {
            for seed: UInt64 in 1...30 {
                setUpWorkspacesForTests()
                let harness = try DifferentialHarness()
                var rng = SplitMix64(seed: seed ^ 0x517c_c1b7_2722_0a95)

                var history: [String] = []
                for step in 0..<45 {
                    let op = Int.random(in: 0..<13, using: &rng)
                    let desc: String
                    switch op {
                    case 0:
                        let p: BinaryLayout.Placement = Bool.random(using: &rng) ? .outer : .inner
                        desc = "placement(\(p.rawValue))"
                        history.append(desc)
                        try harness.applyPlacement(
                            p, context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                    case 1, 2:
                        if harness.windowCount < 9 {
                            let kinds: [DifferentialHarness.CreationKind] = [
                                .normal, .normal, .normal, .dialog, .fixed, .overlay, .listedFloatingApp,
                            ]
                            let kind = kinds[Int.random(in: 0..<kinds.count, using: &rng)]
                            desc = "create(\(kind))"
                            history.append(desc)
                            _ = try harness.createWindow(
                                kind: kind, context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        }
                    case 3:
                        if let id = harness.availableWindowIds.randomElement(using: &rng) {
                            desc = "focus(\(id))"
                            history.append(desc)
                            try harness.focusWindow(
                                id: id, context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        }
                    case 4:
                        let dir = CardinalDirection.allCases[Int.random(in: 0..<4, using: &rng)]
                        desc = "focusDir(\(dir.rawValue))"
                        history.append(desc)
                        try await harness.focusDirection(
                            dir, context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                    case 5:
                        let dir = CardinalDirection.allCases[Int.random(in: 0..<4, using: &rng)]
                        desc = "move(\(dir.rawValue))"
                        history.append(desc)
                        try harness.moveFocused(
                            dir, context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                    case 6:
                        let axis: Orientation = Bool.random(using: &rng) ? .h : .v
                        let delta: CGFloat = [-0.15, -0.05, 0.05, 0.15][Int.random(in: 0..<4, using: &rng)]
                        desc = "resize(\(axis),\(delta))"
                        history.append(desc)
                        try harness.resizeFocused(
                            axis: axis, ratioDelta: delta,
                            context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                    case 7:
                        desc = "toggleFloat"
                        history.append(desc)
                        try harness.toggleFloatFocused(
                            context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                    case 8:
                        if harness.availableWindowIds.count > 1 {
                            desc = "delete"
                            history.append(desc)
                            try harness.deleteFocused(
                                context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        }
                    case 9:
                        if let dest = harness.connectedDisplayIds.filter({ $0 != harness.activeDisplayId })
                            .randomElement(using: &rng)
                        {
                            desc = "transfer(\(dest))"
                            history.append(desc)
                            try harness.transferFocused(
                                to: dest, context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        }
                    case 10:
                        if let suspendedId = harness.suspendedWindowIds.randomElement(using: &rng) {
                            desc = "restore(\(suspendedId))"
                            history.append(desc)
                            try harness.restoreSuspended(
                                id: suspendedId,
                                context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        } else {
                            let reasons: [DifferentialHarness.SuspendReason] = [.minimized, .hidden, .fullscreen]
                            let reason = reasons[Int.random(in: 0..<reasons.count, using: &rng)]
                            desc = "suspend(\(reason.rawValue))"
                            history.append(desc)
                            try harness.suspendFocused(
                                reason: reason,
                                context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        }
                    case 11:
                        if let id = harness.availableWindowIds.randomElement(using: &rng) {
                            let w: CGFloat = [0, 220, 360, 540][Int.random(in: 0..<4, using: &rng)]
                            let h: CGFloat = [0, 140, 240, 360][Int.random(in: 0..<4, using: &rng)]
                            desc = "constraint(\(id),\(Int(w))x\(Int(h)))"
                            history.append(desc)
                            try harness.applyConstraint(
                                id: id, minWidth: w, minHeight: h,
                                context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        }
                    default:
                        if harness.connectedDisplayIds.count > 1, Bool.random(using: &rng),
                            let leaving = harness.connectedDisplayIds.randomElement(using: &rng)
                        {
                            desc = "disconnect(\(leaving))"
                            history.append(desc)
                            try harness.disconnect(
                                displayId: leaving,
                                context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        } else if let offline = harness.offlineDisplayIds.randomElement(using: &rng) {
                            desc = "reconnect(\(offline))"
                            history.append(desc)
                            try harness.reconnect(
                                displayId: offline,
                                context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        } else if let targetDisplay = harness.connectedDisplayIds.randomElement(using: &rng) {
                            let geometries: [(Double, Double, CGFloat, CGFloat, Orientation?)] = [
                                (0, 0, 1440, 900, nil),
                                (1480, 0, 1280, 800, nil),
                                (0, -1200, 1000, 1160, nil),
                                (1480, 200, 620, 420, .h),
                                (0, 0, 900, 900, .v),
                            ]
                            let g = geometries[Int.random(in: 0..<geometries.count, using: &rng)]
                            desc = "screen(\(targetDisplay),\(Int(g.2))x\(Int(g.3)),\(String(describing: g.4)))"
                            history.append(desc)
                            try harness.updateScreen(
                                id: targetDisplay, x: g.0, y: g.1, width: g.2, height: g.3, orientation: g.4,
                                context: "seed=\(seed) step=\(step) \(history.joined(separator: " -> "))")
                        }
                    }
                }
            }
        }
    }
}

@MainActor
private final class DifferentialHarness {
    enum CreationKind { case normal, dialog, fixed, overlay, listedFloatingApp }
    enum SuspendReason: String { case minimized, hidden, fullscreen }

    private struct ProtoSnapshot: Decodable {
        struct DisplaySnap: Decodable {
            let id: String
            let x: Double
            let y: Double
            let w: Double
            let h: Double
            let ids: [UInt32]
        }
        struct RectSnap: Decodable {
            let x: Double
            let y: Double
            let w: Double
            let h: Double
        }
        struct WindowSnap: Decodable {
            let id: UInt32
            let display: String?
            let mode: String
            let rect: RectSnap?
        }
        struct TileSnap: Decodable {
            let id: UInt32
            let display: String
            let x: Double
            let y: Double
            let w: Double
            let h: Double
        }
        let focused: UInt32?
        let activeDisplay: String?
        let displays: [DisplaySnap]
        let offline: [String]
        let windows: [WindowSnap]
        let tiles: [TileSnap]
    }

    private let jsContext: JSContext
    private let state: DisplayLayoutState
    private var monitors: [MonitorInfo]
    private var offlineMonitors: [String: (monitor: TestMonitor, orientation: Orientation?)] = [:]
    private var nextWindowId: UInt32 = 4

    init() throws {
        #expect(ConfigurationApplication.shared.apply("gap = 12\nfloating-apps = ['com.example.float']").isOk)
        let htmlURL = projectRoot.appending(path: "dev-docs/layout-prototype.html")
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        let startRange = try #require(html.range(of: "<script id=\"layout-logic\">"))
        let endRange = try #require(html.range(of: "</script>", range: startRange.upperBound..<html.endIndex))
        let script = String(html[startRange.upperBound..<endRange.lowerBound])

        let ctx = try #require(JSContext())
        var jsException: String?
        ctx.exceptionHandler = { _, exception in
            jsException = exception?.toString()
        }
        ctx.evaluateScript(
            """
            function structuredClone(v) { return v === undefined ? undefined : JSON.parse(JSON.stringify(v)); }
            \(script)
            const __proto = new Layout.DisplayLayoutState();
            __proto.dispatch({ type: 'floatingApps', bundleIds: ['com.example.float'] });
            function __snapshot() {
              const s = __proto.state;
              const tiles = Layout.frames(s);
              return JSON.stringify({
                focused: s.focused,
                activeDisplay: s.activeDisplay,
                displays: s.displays.map(d => ({ id: d.id, x: d.x, y: d.y, w: d.w, h: d.h, ids: Layout.ids(d.root) })),
                offline: s.offline.map(d => d.id),
                windows: Object.values(s.windows).map(w => ({ id: w.id, display: w.display, mode: w.mode, rect: w.rect })),
                tiles: tiles.filter(t => !t.floating).map(t => ({ id: t.id, display: t.display, x: t.x, y: t.y, w: t.w, h: t.h }))
              });
            }
            function __dispatch(payload) {
              __proto.dispatch(JSON.parse(payload));
              return __snapshot();
            }
            """)
        #expect(jsException == nil, Comment(rawValue: jsException ?? ""))
        self.jsContext = ctx

        // Workspace.layoutRect subtracts 1pt of height for macOS multi-display compatibility;
        // adding 1pt to simulated monitor height gives the exact usable area of the JS prototype.
        let screenA = TestMonitor(displayId: "A", name: "A", x: 0, y: 0, isMain: true, width: 1440, height: 901)
        let screenB = TestMonitor(displayId: "B", name: "B", x: 1480, y: 0, width: 1440, height: 901)
        self.monitors = [screenA, screenB]
        unsafe testMonitors = monitors
        let layoutState = DisplayLayoutState(monitors: monitors, pointer: TestPointerAdapter())
        DisplayLayoutState.shared = layoutState
        self.state = layoutState

        // Match Layout.seed(): screenHistory ['A', 'B'] and windows 1, 2, 3 focused in order on A.
        _ = layoutState.workspace(for: screenB).focusWorkspace()
        let workspaceA = layoutState.workspace(for: screenA)
        _ = workspaceA.focusWorkspace()
        for id: UInt32 in 1...3 {
            let w = TestWindow.new(id: id, workspace: workspaceA)
            _ = w.focusWindow()
        }
    }

    var windowCount: Int { state.allWindows.count }
    var activeDisplayId: String { state.focus.workspace.name }
    var connectedDisplayIds: [String] { monitors.map(\.displayId) }
    var offlineDisplayIds: [String] { Array(offlineMonitors.keys).sorted() }
    var availableWindowIds: [UInt32] { state.allWindows.filter(\.isFocusable).map(\.windowId) }
    var suspendedWindowIds: [UInt32] {
        state.allWindows.filter {
            $0.kind == .minimized || $0.kind == .hidden || $0.kind == .nativeFullscreen
        }.map(\.windowId)
    }

    private func dispatchJS(_ dict: [String: Any]) throws -> ProtoSnapshot {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let payload = try #require(String(data: data, encoding: .utf8))
        let fn = try #require(jsContext.objectForKeyedSubscript("__dispatch"))
        let out = try #require(fn.call(withArguments: [payload])?.toString())
        let snap = try JSONDecoder().decode(ProtoSnapshot.self, from: Data(out.utf8))
        syncFloatingRects(from: snap)
        return snap
    }

    private func currentSnapshot() throws -> ProtoSnapshot {
        let fn = try #require(jsContext.objectForKeyedSubscript("__snapshot"))
        let out = try #require(fn.call(withArguments: [])?.toString())
        return try JSONDecoder().decode(ProtoSnapshot.self, from: Data(out.utf8))
    }

    private func syncFloatingRects(from snap: ProtoSnapshot) {
        let displayOrigins = Dictionary(uniqueKeysWithValues: snap.displays.map { ($0.id, ($0.x, $0.y)) })
        for win in snap.windows where win.mode == "floating" {
            guard let rect = win.rect, let display = win.display, let origin = displayOrigins[display],
                let testWin = state.window(for: win.id) as? TestWindow
            else { continue }
            testWin.setAxFrame(
                CGPoint(x: origin.0 + rect.x, y: origin.1 + rect.y),
                CGSize(width: rect.w, height: rect.h))
        }
    }

    func applyPlacement(_ placement: BinaryLayout.Placement, context: String = "") throws {
        #expect(
            ConfigurationApplication.shared.apply(
                "gap = 12\nfloating-apps = ['com.example.float']\nnew-window-placement = '\(placement.rawValue)'"
            ).isOk)
        let snap = try dispatchJS(["type": "placement", "placement": placement.rawValue])
        try assertMatches(snap, context: context)
    }

    @discardableResult
    func createWindow(kind: CreationKind, context: String = "") throws -> UInt32? {
        switch kind {
        case .overlay:
            let snap = try dispatchJS(["type": "create", "kind": "overlay", "bundleId": "com.example.editor"])
            try assertMatches(snap, context: context)
            return nil
        case .normal, .dialog, .fixed, .listedFloatingApp:
            let id = nextWindowId
            nextWindowId += 1
            let jsKind: String
            let bundleId: String
            let swiftKind: WindowKind
            let resizable: Bool
            switch kind {
            case .normal:
                jsKind = "normal"
                bundleId = "com.example.editor"
                swiftKind = .tiled
                resizable = true
            case .dialog:
                jsKind = "dialog"
                bundleId = "com.example.editor"
                swiftKind = .floating
                resizable = true
            case .fixed:
                jsKind = "fixed"
                bundleId = "com.example.editor"
                swiftKind = .floating
                resizable = false
            case .listedFloatingApp:
                jsKind = "normal"
                bundleId = "com.example.float"
                swiftKind = AxUiElementWindowType.window.initialKind(
                    bundleId: bundleId, floatingApps: config.floatingApps)
                resizable = true
            case .overlay:
                die()
            }
            let w = TestWindow.new(id: id, workspace: state.focus.workspace, kind: swiftKind)
            w.isResizable = resizable
            _ = w.focusWindow()
            let snap = try dispatchJS([
                "type": "create", "kind": jsKind, "bundleId": bundleId, "fullscreenButton": "enabled",
            ])
            try assertMatches(snap, context: context)
            return id
        }
    }

    func focusWindow(id: UInt32, context: String = "") throws {
        _ = state.window(for: id)?.focusWindow()
        let snap = try dispatchJS(["type": "focus", "id": id])
        try assertMatches(snap, context: context)
    }

    func focusDirection(_ direction: CardinalDirection, context: String = "") async throws {
        let cmd = FocusCommand(direction: direction)
        _ = await cmd.run(CmdIo())
        let snap = try dispatchJS(["type": "focusDirection", "direction": direction.rawValue])
        try assertMatches(snap, context: context)
    }

    func moveFocused(_ direction: CardinalDirection, context: String = "") throws {
        if let window = state.focus.windowOrNil, window.kind == .tiled, let workspace = window.workspace {
            workspace.layout.move(
                window.windowId, direction: direction, in: workspace.layoutRect,
                gap: CGFloat(config.gap), minimums: workspace.minimums)
            _ = window.focusWindow()
        }
        let snap = try dispatchJS(["type": "move", "direction": direction.rawValue])
        try assertMatches(snap, context: context)
    }

    func resizeFocused(axis: Orientation, ratioDelta: CGFloat, context: String = "") throws {
        if let window = state.focus.windowOrNil, window.kind == .tiled, let workspace = window.workspace {
            let geom = workspace.layout.geometry(in: workspace.layoutRect, gap: CGFloat(config.gap))
            if let leaf = geom.leaves.first(where: { $0.id == window.windowId }) {
                for depth in leaf.path.indices.reversed() {
                    let path = Array(leaf.path.prefix(depth))
                    if let section = geom.sections.first(where: { $0.path == path }), section.axis == axis {
                        let available = section.rect.getDimension(axis) - CGFloat(config.gap)
                        workspace.layout.resize(
                            window.windowId, axis: axis, by: ratioDelta * available,
                            in: workspace.layoutRect, gap: CGFloat(config.gap), minimums: workspace.minimums)
                        break
                    }
                }
            }
        }
        let snap = try dispatchJS([
            "type": "resize", "axis": axis == .h ? "x" : "y", "amount": Double(ratioDelta),
        ])
        try assertMatches(snap, context: context)
    }

    func toggleFloatFocused(context: String = "") throws {
        if let window = state.focus.windowOrNil, let workspace = window.workspace {
            if window.kind == .floating {
                if window.isResizable {
                    state.place(window, on: workspace, kind: .tiled)
                }
            } else if window.kind == .tiled {
                state.place(window, on: workspace, kind: .floating)
            }
            _ = window.focusWindow()
        }
        let snap = try dispatchJS(["type": "float"])
        try assertMatches(snap, context: context)
    }

    func deleteFocused(context: String = "") throws {
        if let window = state.focus.windowOrNil {
            state.removeWindow(window, remember: false)
        }
        let snap = try dispatchJS(["type": "delete"])
        try assertMatches(snap, context: context)
    }

    func transferFocused(to destinationId: String, context: String = "") throws {
        if let window = state.focus.windowOrNil,
            let destMonitor = monitors.first(where: { $0.displayId == destinationId })
        {
            let dest = state.workspace(for: destMonitor)
            if dest !== window.workspace {
                state.place(window, on: dest, kind: window.kind)
            }
            _ = window.focusWindow()
        }
        let snap = try dispatchJS(["type": "transfer", "destination": destinationId])
        try assertMatches(snap, context: context)
    }

    func suspendFocused(reason: SuspendReason, context: String = "") throws {
        if let window = state.focus.windowOrNil, let workspace = window.workspace {
            window.resumeKind = window.kind
            let kind: WindowKind =
                switch reason {
                case .minimized: .minimized
                case .hidden: .hidden
                case .fullscreen: .nativeFullscreen
                }
            state.place(window, on: workspace, kind: kind)
        }
        let snap = try dispatchJS(["type": "suspend", "reason": reason.rawValue])
        try assertMatches(snap, context: context)
    }

    func restoreSuspended(id: UInt32, context: String = "") throws {
        if let window = state.window(for: id), let workspace = window.workspace {
            state.place(window, on: workspace, kind: window.resumeKind)
            _ = window.focusWindow()
        }
        let snap = try dispatchJS(["type": "restore", "id": id])
        try assertMatches(snap, context: context)
    }

    func applyConstraint(id: UInt32, minWidth: CGFloat, minHeight: CGFloat, context: String = "") throws {
        if let window = state.window(for: id) {
            window.minimumSize = CGSize(
                width: max(BinaryLayout.baseline.width, minWidth),
                height: max(BinaryLayout.baseline.height, minHeight))
            window.workspace?.recover()
        }
        let snap = try dispatchJS(["type": "constraint", "id": id, "w": Double(minWidth), "h": Double(minHeight)])
        try assertMatches(snap, context: context)
    }

    func updateScreen(
        id: String, x: Double, y: Double, width: CGFloat, height: CGFloat, orientation: Orientation?,
        context: String = ""
    ) throws {
        if let idx = monitors.firstIndex(where: { $0.displayId == id }) {
            let updated = TestMonitor(
                displayId: id, name: id, x: x, y: y, isMain: monitors[idx].isMain,
                width: width, height: height + 1)
            monitors[idx] = updated
            if !monitors.contains(where: \.isMain), !monitors.isEmpty {
                var first = monitors[0] as! TestMonitor
                first.isMain = true
                monitors[0] = first
            }
            unsafe testMonitors = monitors
            let ws = state.workspace(for: updated)
            ws.orientationOverride = orientation
            state.reconcileMonitors(monitors)
        }
        let jsOrientation = orientation == nil ? "auto" : (orientation == .h ? "x" : "y")
        let snap = try dispatchJS([
            "type": "screen", "display": id,
            "x": x, "y": y, "w": Double(width), "h": Double(height),
            "orientation": jsOrientation,
        ])
        try assertMatches(snap, context: context)
    }

    func disconnect(displayId: String, context: String = "") throws {
        guard monitors.count > 1, let idx = monitors.firstIndex(where: { $0.displayId == displayId }) else { return }
        if let tm = monitors[idx] as? TestMonitor {
            let override = state.workspace(for: tm).orientationOverride
            offlineMonitors[displayId] = (tm, override)
        }
        monitors.remove(at: idx)
        if !monitors.contains(where: \.isMain), !monitors.isEmpty, var first = monitors[0] as? TestMonitor {
            first.isMain = true
            monitors[0] = first
        }
        unsafe testMonitors = monitors
        state.reconcileMonitors(monitors)
        let snap = try dispatchJS(["type": "disconnect", "display": displayId])
        try assertMatches(snap, context: context)
    }

    func reconnect(displayId: String, context: String = "") throws {
        guard let saved = offlineMonitors.removeValue(forKey: displayId) else { return }
        var restored = saved.monitor
        restored.isMain = monitors.isEmpty
        monitors.append(restored)
        unsafe testMonitors = monitors
        state.reconcileMonitors(monitors)
        state.workspace(for: restored).orientationOverride = saved.orientation
        let snap = try dispatchJS(["type": "connect", "display": displayId])
        try assertMatches(snap, context: context)
    }

    func assertMatches(_ label: String) throws {
        let snap = try currentSnapshot()
        syncFloatingRects(from: snap)
        try assertMatches(snap, context: label)
    }

    private func assertMatches(_ snap: ProtoSnapshot, context: String) throws {
        let msg = Comment(rawValue: context)
        try #require(state.focus.windowOrNil?.windowId == snap.focused, msg)
        if let active = snap.activeDisplay {
            try #require(state.focus.workspace.name == active, msg)
        }

        // Compare per-display tiled leaf ordering.
        try #require(Set(state.workspaces.map(\.name)) == Set(snap.displays.map(\.id)), msg)
        for display in snap.displays {
            let ws = state.workspace(named: display.id)
            try #require(ws.layout.windowIds == display.ids, msg)
        }

        // Compare every managed window's mode and assigned display.
        let swiftWindows = Dictionary(uniqueKeysWithValues: state.allWindows.map { ($0.windowId, $0) })
        try #require(Set(swiftWindows.keys) == Set(snap.windows.map(\.id)), msg)
        for protoWin in snap.windows {
            let swiftWin = try #require(swiftWindows[protoWin.id], msg)
            try #require(swiftWin.workspace?.name == protoWin.display, msg)
            switch protoWin.mode {
            case "tiled":
                try #require(swiftWin.kind == .tiled, msg)
            case "floating":
                try #require(swiftWin.kind == .floating, msg)
            case "suspended":
                try #require(
                    swiftWin.kind == .minimized || swiftWin.kind == .hidden || swiftWin.kind == .nativeFullscreen,
                    msg)
            default:
                Issue.record("Unexpected prototype mode \(protoWin.mode)")
            }
        }

        // Compare every tiled window's exact frame coordinates and dimensions.
        for tile in snap.tiles {
            let ws = state.workspace(named: tile.display)
            let swiftRect = try #require(ws.tiledFrames[tile.id], msg)
            try #require(abs(Double(swiftRect.minX) - tile.x) < 0.02, msg)
            try #require(abs(Double(swiftRect.minY) - tile.y) < 0.02, msg)
            try #require(abs(Double(swiftRect.width) - tile.w) < 0.02, msg)
            try #require(abs(Double(swiftRect.height) - tile.h) < 0.02, msg)
        }
    }
}
