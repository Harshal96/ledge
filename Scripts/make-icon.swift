import AppKit

// Native, deterministic artwork in the same teal/mint family as Paperchain.
// The housing + stacked shelf motif is specific to Ledge, not a reused logo.
guard CommandLine.arguments.count == 2 else { fatalError("Usage: make-icon.swift OUTPUT.iconset") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let sizes = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}
for (name, side) in sizes {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 204, yRadius: 204)
    NSGradient(starting: color(0.12, 0.27, 0.29), ending: color(0.035, 0.10, 0.12))!.draw(in: tile, angle: -60)
    color(0.65, 0.98, 0.87, 0.16).setStroke(); tile.lineWidth = 3; tile.stroke()

    // A small camera-housing silhouette anchors the glyph to the top edge.
    NSGraphicsContext.saveGraphicsState(); tile.addClip()
    color(0.018, 0.055, 0.063).setFill()
    NSBezierPath(roundedRect: NSRect(x: 366, y: 806, width: 292, height: 214), xRadius: 48, yRadius: 48).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Receding cards lead into one bright, stable shelf surface.
    for (x, y, width, height, alpha) in [(274.0, 532.0, 476.0, 208.0, 0.30), (238.0, 448.0, 548.0, 224.0, 0.55), (200.0, 298.0, 624.0, 282.0, 1.0)] {
        let card = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: 42, yRadius: 42)
        color(0.59, 0.94, 0.82, alpha).setFill(); card.fill()
        color(0.86, 1, 0.95, 0.20).setStroke(); card.lineWidth = 2; card.stroke()
    }
    color(0.035, 0.16, 0.17, 0.75).setFill()
    NSBezierPath(roundedRect: NSRect(x: 252, y: 440, width: 184, height: 32), xRadius: 16, yRadius: 16).fill()
    color(0.035, 0.16, 0.17, 0.34).setFill()
    NSBezierPath(roundedRect: NSRect(x: 252, y: 374, width: 308, height: 22), xRadius: 11, yRadius: 11).fill()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 650, y: 376)); arrow.line(to: NSPoint(x: 702, y: 428)); arrow.line(to: NSPoint(x: 650, y: 480))
    arrow.lineWidth = 20; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    color(0.035, 0.16, 0.17, 0.8).setStroke(); arrow.stroke()
    let rail = NSBezierPath(); rail.move(to: NSPoint(x: 250, y: 224)); rail.line(to: NSPoint(x: 774, y: 224))
    rail.lineWidth = 20; rail.lineCapStyle = .round
    color(0.60, 0.95, 0.84).setStroke(); rail.stroke()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try png.write(to: destination.appendingPathComponent(name + ".png"))
}
