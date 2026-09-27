import AppBundle
import SwiftUI

@main
struct TileApp: App {
    private let viewModel = TrayMenuModel.shared
    private let messageModel = MessageModel.shared
    @Environment(\.openWindow) var openWindow: OpenWindowAction

    init() {
        initAppBundle()
    }

    var body: some Scene {
        menuBar(viewModel: viewModel)
        getMessageWindow(messageModel: messageModel)
            .onChange(of: messageModel.message, initial: true) {
                if messageModel.message != nil {
                    openWindow(id: messageWindowId)
                }
            }
    }
}
