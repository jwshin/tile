extension MonitorInfo {
    @MainActor
    var visibleRectPaddedByOuterGaps: Rect {
        let topLeft = visibleRect.topLeftCorner
        let gap = Double(config.gap)
        return Rect(
            topLeftX: topLeft.x + gap,
            topLeftY: topLeft.y + gap,
            width: visibleRect.width - gap - gap,
            height: visibleRect.height - gap - gap,
        )
    }
}
