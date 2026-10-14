// Renders the app icon at 1024x1024 following the macOS icon grid (824pt body, 100pt margin).
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Body with drop shadow.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor(srgbRed: 1.0, green: 0.62, blue: 0.16, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [
    NSColor(srgbRed: 1.00, green: 0.80, blue: 0.30, alpha: 1),
    NSColor(srgbRed: 0.98, green: 0.52, blue: 0.12, alpha: 1),
])!.draw(in: body, angle: -90)

// Voice waveform: rounded bars, tallest in the middle.
let heights: [CGFloat] = [170, 330, 500, 640, 460, 300, 180]
let barWidth: CGFloat = 62
let gap: CGFloat = 32
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
NSGraphicsContext.saveGraphicsState()
let barShadow = NSShadow()
barShadow.shadowColor = NSColor(srgbRed: 0.55, green: 0.25, blue: 0.0, alpha: 0.35)
barShadow.shadowBlurRadius = 24
barShadow.shadowOffset = NSSize(width: 0, height: -10)
barShadow.set()
for (i, h) in heights.enumerated() {
    let x = 512 - total / 2 + CGFloat(i) * (barWidth + gap)
    let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 512 - h / 2, width: barWidth, height: h), xRadius: barWidth / 2, yRadius: barWidth / 2)
    // The centre bar is the "live" one, in the navy used across the Infinity icons.
    (i == 3 ? NSColor(srgbRed: 0.20, green: 0.24, blue: 0.40, alpha: 1) : NSColor(srgbRed: 1, green: 0.99, blue: 0.96, alpha: 1)).setFill()
    bar.fill()
}
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

image.unlockFocus()
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = image.size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
