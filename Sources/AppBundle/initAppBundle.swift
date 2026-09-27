import AppKit
import Common
import Foundation

@MainActor public func initAppBundle() {
    _ = Task {
        initTerminationHandler()
        initAppOptions()
        let competingApp = NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != myPid
                && ["bobko.aerospace", "bobko.aerospace.debug", stableAppId, appId].contains(
                    $0.bundleIdentifier ?? "")
        }
        if let competingApp {
            MessageModel.shared.message = Message(
                body:
                    "Quit \(competingApp.localizedName ?? "the other tile instance") before starting this window manager."
            )
            return
        }
        await waitForAccessibilityPermission_nonCancellable()
        if isDebug {
            interceptTermination(SIGINT)
            interceptTermination(SIGTERM)
        }

        bootstrapConfiguration()
        let configResult = ConfigurationApplication.shared.reload()
        MessageModel.shared.message = configResult.diagnostics.map { Message(body: $0) }

        GlobalObserver.initObserver()
        DisplayLayoutState.shared.reconcileMonitors(monitorInfos)  // init workspaces
        _ = DisplayLayoutState.shared.workspaces.first?.focusWorkspace()
        await ActionExecution.shared.refresh(
            .startup,
            // It's important for the first initialization to be non cancellable
            // so initialization completes before subsequent refreshes
            assumeCancellable: false,
            layoutWorkspaces: false,
        )
        try await ActionExecution.shared.runSession(.startup, .forceRun) {}
    }
}

@MainActor private func bootstrapConfiguration() {
    let result = ConfigurationApplication.shared.reload(from: defaultConfigUrl)
    let msg = """
        Can't load default config. Your installation is probably corrupted.
        Please don't modify \(defaultConfigUrl.description.singleQuoted)

        \(result.diagnostics ?? "")
        """
    check(result.isOk, msg)
}

struct AppOptions: Sendable {
    var isReadOnly: Bool = false
}

private let appHelp = """
    USAGE: \(CommandLine.arguments.first ?? "tile.app/Contents/MacOS/tile") [<options>]

    OPTIONS:
      -h, --help              Print help
      -v, --version           Print tile.app version
      --read-only             Disable window management.
                              Useful for inspecting startup without moving windows.
    """

nonisolated(unsafe) private var _appOptions = AppOptions()
var appOptions: AppOptions { unsafe _appOptions }
private func initAppOptions() {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.contains(where: { $0 == "-h" || $0 == "--help" }) {
        exit(EXIT_CODE_ZERO, out: appHelp)
    }
    var index = 0
    while index < args.count {
        let current = args[index]
        index += 1
        switch current {
        case "--version", "-v":
            exit(EXIT_CODE_ZERO, out: appVersion)
        case "--read-only":  // todo rename to '--disabled' and unite with disabled feature
            unsafe _appOptions.isReadOnly = true
        case "-NSDocumentRevisionsDebugMode" where isDebug:
            // Skip Xcode CLI args.
            // Usually it's '-NSDocumentRevisionsDebugMode NO'/'-NSDocumentRevisionsDebugMode YES'
            while args.getOrNil(atIndex: index)?.starts(with: "-") == false { index += 1 }
        default:
            exit(EXIT_CODE_TWO, err: "Unrecognized flag \(current.singleQuoted)")
        }
    }
}
