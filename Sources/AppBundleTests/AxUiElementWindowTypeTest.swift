import AppKit
import Common
import Testing

@testable import AppBundle

extension CoreTests {
    struct AxWindowKindTest {
        var name: String { String(describing: Self.self) }
        @Test func test() throws {
            try checkAxDumpsRecursive(projectRoot.appending(path: "./axDumps"))
        }

        @Test(arguments: [nil, false, true] as [Bool?])
        func claudeStandardWindowTilesWithoutNativeFullscreenControls(fullscreenEnabled: Bool?) {
            let type = classifyClaudeWindow(fullscreenEnabled: fullscreenEnabled)
            #expect(type == .window)
            #expect(type.initialKind(bundleId: claudeBundleId, floatingApps: []) == .tiled)
            #expect(type.initialKind(bundleId: claudeBundleId, floatingApps: [claudeBundleId]) == .floating)
        }

        @Test func claudeDialogsAndOverlaysStayOutOfTheTiledLayout() {
            #expect(classifyClaudeWindow(subrole: kAXDialogSubrole) == .dialog)
            #expect(classifyClaudeWindow(subrole: kAXFloatingWindowSubrole) == .dialog)
            #expect(classifyClaudeWindow(level: .alwaysOnTopWindow) == .popup)
            #expect(classifyClaudeWindow(level: .unknown(windowLevel: 25)) == .popup)
            #expect(classifyClaudeWindow(level: nil) == .popup)
        }

        @Test func fullscreenControlExceptionDoesNotApplyToOtherApps() {
            let window = standardWindowWithoutButtons()
            #expect(window.getWindowType(axApp: [:], nil, .regular, .normalWindow) == .dialog)
        }

        @MainActor @Test func claudeMainWindowSharesTheScreenWithAnExistingTile() throws {
            setUpWorkspacesForTests()
            let workspace = focus.workspace
            let existing = TestWindow.new(id: 1, workspace: workspace)
            let initialWidth = try #require(workspace.tiledFrames[existing.windowId]).width
            let type = classifyClaudeWindow()
            let claude = TestWindow.new(
                id: 2, workspace: workspace,
                kind: type.initialKind(bundleId: claudeBundleId, floatingApps: []))
            #expect(claude.kind == .tiled)
            #expect(workspace.layout.windowIds.count == 2)
            let existingFrame = try #require(workspace.tiledFrames[existing.windowId])
            #expect(existingFrame.width < initialWidth)
        }
    }
}

private let claudeBundleId = "com.anthropic.claudefordesktop"

// Synthetic compatibility cases, not a captured native AX dump.
private func standardWindowWithoutButtons() -> [String: Json] {
    [
        "AXSubrole": .string(kAXStandardWindowSubrole),
        "AXFocused": .bool(true),
        "AXMain": .bool(true),
        "AXTitle": .string("Claude"),
        "tile.axWindowId": .int(Int64(2)),
    ]
}

private func classifyClaudeWindow(
    fullscreenEnabled: Bool? = nil,
    subrole: String = kAXStandardWindowSubrole,
    level: MacOsWindowLevel? = .normalWindow,
) -> AxUiElementWindowType {
    var window = standardWindowWithoutButtons()
    window["AXSubrole"] = .string(subrole)
    if let fullscreenEnabled {
        window["AXFullScreenButton"] = .dict(["AXEnabled": .bool(fullscreenEnabled)])
    }
    return window.getWindowType(axApp: [:], KnownBundleId(rawValue: claudeBundleId), .regular, level)
}

func checkAxDumpsRecursive(_ dir: URL) throws {
    for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
        if file.isDirectory {
            try checkAxDumpsRecursive(file)
            continue
        }
        if file.pathExtension == "md" { continue }

        let rawJson =
            try JSONSerialization.jsonObject(with: Data.init(contentsOf: file), options: [.json5Allowed])
            as! [String: Any]
        let json = Json.newOrDieRecursive(rawJson).asDictOrDie
        let app = json["tile.AXApp"]!.asDictOrDie
        let appBundleId = (rawJson["tile.App.appBundleId"] as? String).flatMap { KnownBundleId.init(rawValue: $0) }
        let windowLevel = json["tile.windowLevel"].map { MacOsWindowLevel.fromJson($0) ?? dieT() }
        let activationPolicy: NSApplication.ActivationPolicy = .from(
            string: rawJson["tile.App.nsApp.activationPolicy"] as! String)
        assertEquals(
            json.getWindowType(axApp: app, appBundleId, activationPolicy, windowLevel),
            AxUiElementWindowType(rawValue: rawJson["tile.AxUiElementWindowType"] as? String ?? dieT()),
            additionalMsg: "\(file.path()):0:0: AxUiElementWindowType doesn't match",
        )
        assertEquals(
            json.isDialogHeuristic(appBundleId, windowLevel),
            rawJson["tile.AxUiElementWindowType_isDialogHeuristic"] as? Bool ?? dieT(),
            additionalMsg: "\(file.path()):0:0: AxUiElementWindowType_isDialogHeuristic doesn't match",
        )
    }
}

extension [String: Json]: AxUiElementMock {
    public func get<Attr>(_ attr: Attr) -> Attr.T? where Attr: ReadableAttr {
        guard let value = self[attr.key] else {
            return isSynthetic ? dieT("\(self) doesn't contain \(attr.key)") : nil
        }
        if let value = value.rawValue {
            return attr.getter(value as AnyObject)
                ?? dieT("Value \(value) (of type \(Swift.type(of: value))) isn't convertible to \(attr.key)")
        } else {
            return nil
        }
    }

    private var isSynthetic: Bool { self[kAXTileSynthetic] != nil }

    public func containingWindowId() -> CGWindowID? { _containingWindowId() }

    private func _containingWindowId() -> CGWindowID {
        let windowId = self["tile.axWindowId"]?.asInt64OrNil ?? dieT()
        return UInt32.init(exactly: windowId).orDie()
    }
}

extension NSApplication.ActivationPolicy {
    static func from(string: String) -> NSApplication.ActivationPolicy {
        switch string {
        case "regular": .regular
        case "accessory": .accessory
        case "prohibited": .prohibited
        default: dieT("Unknown ActivationPolicy \(string)")
        }
    }
}

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
