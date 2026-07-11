// Generates AppIcon.icns: flat vector bear face on a warm gradient rounded rect.
// Usage: swift scripts/make-icon.swift <output-dir>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let iconsetPath = "\(outputDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
}

let bgTop = rgb(0.36, 0.25, 0.17)
let bgBottom = rgb(0.16, 0.11, 0.08)
let fur = rgb(0.76, 0.55, 0.38)
let furDark = rgb(0.62, 0.43, 0.28)
let cream = rgb(0.94, 0.85, 0.72)
let dark = rgb(0.16, 0.11, 0.08)

func circle(at center: NSPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - radius, y: center.y - radius,
        width: radius * 2, height: radius * 2
    )).fill()
}

func drawIcon(pixels: Int) -> NSImage {
    let s = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // Background: rounded rect with vertical gradient
    let inset = s * 0.05
    let bgRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(starting: bgBottom, ending: bgTop)?.draw(in: bgPath, angle: 90)

    let headCenter = NSPoint(x: s * 0.5, y: s * 0.46)
    let headRadius = s * 0.28

    // Ears (behind head), inner ears drawn after head on the visible halves
    let earOffset = NSPoint(x: s * 0.195, y: s * 0.235)
    let leftEar = NSPoint(x: headCenter.x - earOffset.x, y: headCenter.y + earOffset.y)
    let rightEar = NSPoint(x: headCenter.x + earOffset.x, y: headCenter.y + earOffset.y)
    circle(at: leftEar, radius: s * 0.105, color: furDark)
    circle(at: rightEar, radius: s * 0.105, color: furDark)

    // Head
    circle(at: headCenter, radius: headRadius, color: fur)

    // Inner ears (nudged outward so they sit on the visible part of the ear)
    let innerNudge = s * 0.028
    circle(at: NSPoint(x: leftEar.x - innerNudge, y: leftEar.y + innerNudge), radius: s * 0.048, color: cream)
    circle(at: NSPoint(x: rightEar.x + innerNudge, y: rightEar.y + innerNudge), radius: s * 0.048, color: cream)

    // Muzzle
    cream.setFill()
    let muzzleSize = NSSize(width: s * 0.26, height: s * 0.185)
    NSBezierPath(ovalIn: NSRect(
        x: headCenter.x - muzzleSize.width / 2,
        y: headCenter.y - s * 0.19,
        width: muzzleSize.width,
        height: muzzleSize.height
    )).fill()

    // Nose
    dark.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: headCenter.x - s * 0.042,
        y: headCenter.y - s * 0.075,
        width: s * 0.084,
        height: s * 0.058
    )).fill()

    // Eyes
    circle(at: NSPoint(x: headCenter.x - s * 0.105, y: headCenter.y + s * 0.055), radius: s * 0.026, color: dark)
    circle(at: NSPoint(x: headCenter.x + s * 0.105, y: headCenter.y + s * 0.055), radius: s * 0.026, color: dark)

    // Play badge (bottom-right, overlapping the head edge)
    let badgeCenter = NSPoint(x: s * 0.72, y: s * 0.265)
    let badgeRadius = s * 0.105
    circle(at: badgeCenter, radius: badgeRadius, color: cream)
    dark.setFill()
    let triangle = NSBezierPath()
    let tr = badgeRadius * 0.52
    triangle.move(to: NSPoint(x: badgeCenter.x - tr * 0.6, y: badgeCenter.y + tr))
    triangle.line(to: NSPoint(x: badgeCenter.x - tr * 0.6, y: badgeCenter.y - tr))
    triangle.line(to: NSPoint(x: badgeCenter.x + tr * 1.1, y: badgeCenter.y))
    triangle.close()
    triangle.fill()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to filePath: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(filePath)")
    }
    try! png.write(to: URL(fileURLWithPath: filePath))
}

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for spec in specs {
    writePNG(drawIcon(pixels: spec.pixels), to: "\(iconsetPath)/\(spec.name)")
}
print("iconset written to \(iconsetPath)")
