// Generates Resources/AppIcon.icns. Run: swift Tools/makeicon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)

    let colors = [NSColor(calibratedRed: 0.35, green: 0.52, blue: 0.98, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.16, green: 0.28, blue: 0.72, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
    ctx.saveGState()
    path.addClip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    ctx.restoreGState()

    if let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .medium)
        let glyph = symbol.withSymbolConfiguration(config)!
        let tinted = NSImage(size: glyph.size, flipped: false) { rect in
            NSColor.white.set()
            rect.fill()
            glyph.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        let target = CGRect(x: (size - glyph.size.width) / 2,
                            y: (size - glyph.size.height) / 2,
                            width: glyph.size.width, height: glyph.size.height)
        tinted.draw(in: target)
    }
    image.unlockFocus()
    return image
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (px, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
                   (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
                   (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
    let img = drawIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("iconset ready")
