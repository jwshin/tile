import AppKit

/// A small template version of the logo's alternating divisions, drawn at menu-bar weight.
@MainActor enum TileMenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            let border = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 16), xRadius: 2, yRadius: 2)
            border.lineWidth = 1.2
            border.stroke()
            let divisions = NSBezierPath()
            for (start, end) in [
                (NSPoint(x: 7.7, y: 1), NSPoint(x: 7.7, y: 17)),
                (NSPoint(x: 7.7, y: 7.7), NSPoint(x: 17, y: 7.7)),
                (NSPoint(x: 11.8, y: 7.7), NSPoint(x: 11.8, y: 17)),
                (NSPoint(x: 11.8, y: 11.8), NSPoint(x: 17, y: 11.8)),
                (NSPoint(x: 14.1, y: 11.8), NSPoint(x: 14.1, y: 17)),
                (NSPoint(x: 14.1, y: 14.3), NSPoint(x: 17, y: 14.3)),
            ] {
                divisions.move(to: start)
                divisions.line(to: end)
            }
            divisions.lineWidth = 1
            divisions.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
