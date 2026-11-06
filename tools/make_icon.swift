import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(srgbRed: 0.14, green: 0.38, blue: 0.86, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 200, yRadius: 200).fill()
        NSColor.white.setFill()
        NSColor.white.setStroke()
        NSBezierPath(roundedRect: NSRect(x: 402, y: 410, width: 220, height: 380), xRadius: 110, yRadius: 110).fill()
        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: 316, y: 520))
        stand.line(to: NSPoint(x: 316, y: 462))
        stand.curve(to: NSPoint(x: 708, y: 462), controlPoint1: NSPoint(x: 316, y: 208), controlPoint2: NSPoint(x: 708, y: 208))
        stand.line(to: NSPoint(x: 708, y: 520))
        stand.lineWidth = 48
        stand.lineCapStyle = .round
        stand.stroke()
        let foot = NSBezierPath()
        foot.move(to: NSPoint(x: 512, y: 270)); foot.line(to: NSPoint(x: 512, y: 202))
        foot.move(to: NSPoint(x: 408, y: 196)); foot.line(to: NSPoint(x: 616, y: 196))
        foot.lineWidth = 48; foot.lineCapStyle = .round; foot.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
