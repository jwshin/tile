import Common

struct FocusMonitorCommand: Command {
    let target: MonitorTarget
    let invalidatesRestoration = false

    func run(_ io: CmdIo) -> BinaryExitCode {
        switch target.resolve(focus.workspace.workspaceMonitor) {
        case .success(let monitor): .from(bool: monitor.activeWorkspace.focusWorkspace())
        case .failure(let message): .fail(io.err(message))
        }
    }
}

enum MonitorTarget: Sendable {
    case direction(CardinalDirection)
    case relative(NextPrev)

    @MainActor func resolve(_ currentMonitor: MonitorInfo) -> Result<MonitorInfo, String> {
        switch self {
        case .direction(let direction):
            guard let (monitors, index) = currentMonitor.findRelativeMonitor(inDirection: direction),
                let monitor = monitors.getOrNil(atIndex: index)
            else {
                return .failure("No monitor in direction \(direction)")
            }
            return .success(monitor)
        case .relative(let nextPrev):
            let monitors = sortedMonitorInfos
            guard let index = monitors.firstIndex(where: { $0.displayId == currentMonitor.displayId }),
                let monitor = monitors.get(wrappingIndex: index + (nextPrev == .next ? 1 : -1))
            else {
                return .failure("Can't find current monitor")
            }
            return .success(monitor)
        }
    }
}

extension MonitorInfo {
    func relation(to monitor: MonitorInfo) -> Orientation {
        guard let otherYRange = monitor.rect.minY.until(excl: monitor.rect.maxY) else { return .h }
        guard let myYRange = rect.minY.until(excl: rect.maxY) else { return .h }
        return myYRange.overlaps(otherYRange) ? .h : .v
    }

    func findRelativeMonitor(inDirection direction: CardinalDirection) -> (
        monitorsInDirection: [MonitorInfo], index: Int
    )? {
        let currentMonitor = self
        let monitors = sortedMonitorInfos.filter {
            currentMonitor.rect.topLeftCorner == $0.rect.topLeftCorner
                || $0.relation(to: currentMonitor) == direction.orientation
        }
        guard let index = monitors.firstIndex(where: { $0.rect.topLeftCorner == currentMonitor.rect.topLeftCorner })
        else { return nil }
        return (monitors, index + direction.focusOffset)
    }
}
