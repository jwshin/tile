#!/usr/bin/env swift
import AppKit
import Foundation

// One set of alternating binary divisions generates the vector mark and macOS icon.
let panes: [(Double, Double, Double, Double, String)] = [
    (46, 46, 166, 420, "E44838"),
    (226, 46, 240, 166, "F6F2E8"),
    (226, 226, 100, 240, "2669B8"),
    (340, 226, 126, 100, "F3C542"),
    (340, 340, 52, 126, "F6F2E8"),
    (406, 340, 60, 56, "F6F2E8"),
    (406, 410, 60, 56, "E44838"),
]
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("resources")
let output = root.appendingPathComponent(".release/logo")
let iconset = output.appendingPathComponent("tile.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let rectangles = panes.map { x, y, w, h, hex in
    "<rect x=\"\(Int(x))\" y=\"\(Int(y))\" width=\"\(Int(w))\" height=\"\(Int(h))\" fill=\"#\(hex)\"/>"
}.joined(separator: "\n    ")
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-labelledby="title description">
  <title id="title">tile</title>
  <desc id="description">A screen divided into nested red, blue, yellow, and ivory panes by alternating binary splits.</desc>
  <defs><clipPath id="screen"><rect x="46" y="46" width="420" height="420" rx="30"/></clipPath></defs>
  <rect x="32" y="32" width="448" height="448" rx="44" fill="#202423"/>
  <g clip-path="url(#screen)">
    \(rectangles)
  </g>
</svg>

"""
try svg.write(to: resources.appendingPathComponent("tile.svg"), atomically: true, encoding: .utf8)

func color(_ hex: String) -> CGColor {
    let rgb = UInt32(hex, radix: 16)!
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        Double((rgb >> 16) & 255) / 255, Double((rgb >> 8) & 255) / 255,
        Double(rgb & 255) / 255, 1,
    ])!
}

func render(_ size: Int, to url: URL) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: Double(size) / 512, y: Double(size) / 512)
    context.translateBy(x: 0, y: 512)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(color("202423"))
    context.addPath(CGPath(roundedRect: CGRect(x: 32, y: 32, width: 448, height: 448),
                           cornerWidth: 44, cornerHeight: 44, transform: nil))
    context.fillPath()
    context.addPath(CGPath(roundedRect: CGRect(x: 46, y: 46, width: 420, height: 420),
                           cornerWidth: 30, cornerHeight: 30, transform: nil))
    context.clip()
    for (x, y, w, h, hex) in panes {
        context.setFillColor(color(hex))
        context.fill(CGRect(x: x, y: y, width: w, height: h))
    }
    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    try image.representation(using: .png, properties: [:])!.write(to: url)
}

for size in [16, 32, 128, 256, 512] {
    try render(size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(512, to: resources.appendingPathComponent("tile.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("tile.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Rendered resources/tile.svg, tile.png, and tile.icns")
