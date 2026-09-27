import AppKit
import Common

struct ReloadConfigCommand: Command {
    let shouldResetClosedWindowsCache = false

    func run(_ io: CmdIo) async -> BinaryExitCode {
        let result = await reloadConfig_nonCancellable()
        if !result.stdout.isEmpty {
            io.out(result.stdout)
        }
        return .from(bool: result.isOk)
    }
}

struct ReloadConfigResult {
    let isOk: Bool
    let stdout: String
}

@MainActor func reloadConfig_nonCancellable(
    forceConfigUrl: URL? = nil,
) async -> ReloadConfigResult {
    let result = readConfig(forceConfigUrl: forceConfigUrl)
    let parseResult = result.parseConfigResult
    let errors = parseResult.errors.map(\.description)

    if errors.isEmpty {
        MessageModel.shared.message = nil
    } else {
        let header = "Failed to parse \(result.configUrl.path.singleQuoted). \(errors.count) error(s)."
        MessageModel.shared.message = Message(body: header + "\n\n" + errors.joined(separator: "\n\n"))
    }
    if parseResult.allowReloadConfig {
        resetHotKeys()
        config = parseResult.config
        syncHotkeys()
    }
    return ReloadConfigResult(isOk: errors.isEmpty, stdout: errors.joined(separator: "\n\n"))
}
