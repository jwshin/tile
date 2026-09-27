import Common
import SwiftUI

@MainActor
public func menuBar(viewModel: TrayMenuModel) -> some Scene {
    MenuBarExtra {
        Text(appName)
        if viewModel.axPermissionStatus != .granted {
            Button("Grant Accessibility permission") { viewModel.axPermissionStatus = .waitingWithPrompt }
        } else {
            if viewModel.secureInput { Text("Secure Input is blocking keyboard shortcuts") }
            Button(viewModel.isEnabled ? "Disable tiling" : "Enable tiling") {
                _ = Task {
                    try await runLightSession(.menuBarButton, .forceRun) {
                        _ = await Action.toggleTiling.run()
                    }
                }
            }
            openConfigButton()
            reloadConfigButton()
        }
        Divider()
        Button("Quit") {
            terminationHandler?.beforeTermination()
            terminateApp()
        }.keyboardShortcut("Q", modifiers: .command)
    } label: {
        Text(
            viewModel.axPermissionStatus != .granted
                ? "tile !" : viewModel.isEnabled ? viewModel.trayText : "tile paused")
    }
}

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let editor = getTextEditorToOpenConfig()
    let button = Button("Open config in '\(editor.lastPathComponent)'") {
        let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
        switch findCustomConfigUrl() {
        case .file(let url):
            url.open(with: editor)
        case .noCustomConfigExists:
            _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
            fallbackConfig.open(with: editor)
        }
    }.keyboardShortcut(",", modifiers: .command)
    switch showShortcutGroup {
    case true: shortcutGroup(label: Text("⌘ ,"), content: button)
    case false: button
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false) -> some View {
    do {
        let token = RunSessionGuard.forceRun
        let button = Button("Reload config") {
            _ = Task {
                try await runLightSession(.menuBarButton, token) {
                    _ = await reloadConfig_nonCancellable()
                }
            }
        }.keyboardShortcut("R", modifiers: .command)
        switch showShortcutGroup {
        case true: shortcutGroup(label: Text("⌘ R"), content: button)
        case false: button
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: 6) {
            label
                .foregroundStyle(Color.secondary)
            content
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" }  // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}
