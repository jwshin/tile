import Common
import Observation
import SwiftUI

@MainActor
public func getMessageWindow(messageModel: MessageModel) -> some Scene {
    // Using SwiftUI.Window because another class in tile is already called Window
    SwiftUI.Window(appName, id: messageWindowId) {
        MessageView(model: messageModel)
            .onAppear {
                // Set activation policy; otherwise, tile windows won't be able to receive focus and accept keyboard input
                NSApp.setActivationPolicy(.accessory)
            }
            .windowMinimizeBehavior(.disabled)
    }
    .windowResizability(.contentMinSize)
    .windowLevel(.floating)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
}

public let messageWindowId = "\(appName).messageView"

struct MessageView: View {
    let model: MessageModel
    @Environment(\.dismiss) private var dismiss: DismissAction

    public var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 48))
                Text("tile config diagnostics")
                    .padding(.horizontal)
                    .focusable()
            }
            .padding()
            ScrollView {
                Text(model.message?.body ?? "")
                    .font(.system(size: 12).monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal)
            HStack {
                Spacer()
                if model.message != nil {
                    reloadConfigButton(showShortcutGroup: true)
                    openConfigButton(showShortcutGroup: true)
                }
                let closeButton = Button("Close") { model.message = nil }.keyboardShortcut(.defaultAction)
                shortcutGroup(label: Image(systemName: "return.left"), content: closeButton)
            }
            .padding()
        }
        .textSelection(.enabled)
        .frame(minWidth: 480, maxWidth: 960, minHeight: 200)
        .onChange(of: model.message) {
            if model.message == nil {
                self.dismiss()
            }
        }
        .onDisappear {
            // If user closes the screen with the macOS native close (x) button and then the error is still the same, this window will not appear again
            model.message = nil
        }
    }
}

@MainActor @Observable
public final class MessageModel {
    public static let shared = MessageModel()
    public var message: Message? = nil

    private init() {}
}

public struct Message: Hashable, Equatable {
    public let body: String
}

@MainActor extension MessageModel {
    func present(_ result: CmdResult, for action: Action) {
        if action == .reloadConfig && result.exitCode == .succ { message = nil }
        if result.exitCode == .fail && !result.diagnostics.isEmpty {
            message = Message(body: result.diagnostics)
        }
    }
}
