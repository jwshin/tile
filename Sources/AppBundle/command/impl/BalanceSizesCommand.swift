import AppKit
import Common
import Foundation

struct BalanceSizesCommand: Command {
    let invalidatesRestoration = true

    func run(_ io: CmdIo) -> BinaryExitCode {
        let target = focus
        balance(target.workspace.rootTilingContainer)
        return .succ
    }
}

@MainActor
private func balance(_ parent: TilingContainer) {
    for child in parent.children {
        child.setWeight(parent.orientation, 1)
        if let child = child as? TilingContainer {
            balance(child)
        }
    }
}
