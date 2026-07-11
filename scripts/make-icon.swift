// Generates AppIcon.icns: dark rounded-rect background with a bear emoji + play triangle.
// Usage: swift scripts/make-icon.swift <output-dir>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let iconsetPath = "\(outputDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let inset = size * 0.05
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.13, blue: 0.10, alpha: 1),
        ending: NSColor(calibratedRed: 0.35, green: 0.24, blue: 0.15, alpha: 1)
    )
    gradient?.draw(in: path, angle: -90)

    let emoji = "🐻" as NSString
    let fontSize = size * 0.55
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
    let textSize = emoji.size(withAttributes: attrs)
    emoji.draw(
        at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2 + size * 0.02),
        withAttributes: attrs
    )

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixels: Int, to filePath: String) {
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
    writePNG(drawIcon(pixels: spec.pixels), pixels: spec.pixels, to: "\(iconsetPath)/\(spec.name)")
}
print("iconset written to \(iconsetPath)")
