import Common

/// The complete set of bindable actions. Behavior is fixed; only shortcuts are configurable.
enum Action: String, CaseIterable, Sendable {
    case focusLeft = "focus-left"
    case focusDown = "focus-down"
    case focusUp = "focus-up"
    case focusRight = "focus-right"
    case moveLeft = "move-left"
    case moveDown = "move-down"
    case moveUp = "move-up"
    case moveRight = "move-right"
    case swapLeft = "swap-left"
    case swapDown = "swap-down"
    case swapUp = "swap-up"
    case swapRight = "swap-right"
    case nextMonitor = "next-monitor"
    case previousMonitor = "previous-monitor"
    case leftMonitor = "left-monitor"
    case downMonitor = "down-monitor"
    case upMonitor = "up-monitor"
    case rightMonitor = "right-monitor"
    case moveToNextMonitor = "move-to-next-monitor"
    case moveToPreviousMonitor = "move-to-previous-monitor"
    case moveToMonitorLeft = "move-to-monitor-left"
    case moveToMonitorDown = "move-to-monitor-down"
    case moveToMonitorUp = "move-to-monitor-up"
    case moveToMonitorRight = "move-to-monitor-right"
    case balanceSizes = "balance-sizes"
    case close = "close"
    case toggleTiling = "toggle-tiling"
    case fullscreen = "fullscreen"
    case toggleSplit = "toggle-split"
    case toggleFloating = "toggle-floating"
    case reloadConfig = "reload-config"
    case shrink = "shrink"
    case grow = "grow"

    var command: any Command {
        switch self {
        case .focusLeft: FocusCommand(direction: .left)
        case .focusDown: FocusCommand(direction: .down)
        case .focusUp: FocusCommand(direction: .up)
        case .focusRight: FocusCommand(direction: .right)
        case .moveLeft: MoveCommand(direction: .left)
        case .moveDown: MoveCommand(direction: .down)
        case .moveUp: MoveCommand(direction: .up)
        case .moveRight: MoveCommand(direction: .right)
        case .swapLeft: SwapCommand(direction: .left)
        case .swapDown: SwapCommand(direction: .down)
        case .swapUp: SwapCommand(direction: .up)
        case .swapRight: SwapCommand(direction: .right)
        case .nextMonitor: FocusMonitorCommand(target: .relative(.next))
        case .previousMonitor: FocusMonitorCommand(target: .relative(.prev))
        case .leftMonitor: FocusMonitorCommand(target: .direction(.left))
        case .downMonitor: FocusMonitorCommand(target: .direction(.down))
        case .upMonitor: FocusMonitorCommand(target: .direction(.up))
        case .rightMonitor: FocusMonitorCommand(target: .direction(.right))
        case .moveToNextMonitor: MoveNodeToMonitorCommand(target: .relative(.next))
        case .moveToPreviousMonitor: MoveNodeToMonitorCommand(target: .relative(.prev))
        case .moveToMonitorLeft: MoveNodeToMonitorCommand(target: .direction(.left))
        case .moveToMonitorDown: MoveNodeToMonitorCommand(target: .direction(.down))
        case .moveToMonitorUp: MoveNodeToMonitorCommand(target: .direction(.up))
        case .moveToMonitorRight: MoveNodeToMonitorCommand(target: .direction(.right))
        case .balanceSizes: BalanceSizesCommand()
        case .close: CloseCommand()
        case .toggleTiling: EnableCommand()
        case .fullscreen: FullscreenCommand()
        case .toggleSplit: LayoutCommand(change: .orientation)
        case .toggleFloating: LayoutCommand(change: .floating)
        case .reloadConfig: ReloadConfigCommand()
        case .shrink: ResizeCommand(grow: false)
        case .grow: ResizeCommand(grow: true)
        }
    }

}
