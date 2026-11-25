// Draws the app icon: the rounded play shape of PixelPlayer on Android with the app's own note, in the Mac app's blue,
// on the macOS icon grid (1024 canvas, a rounded square of 824 with room for its shadow).
//   swift scripts/make-icon.swift <out.png> [size]
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1024 : 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
let s = CGFloat(size) / 1024
ctx.scaleBy(x: s, y: s)
// Work top-down, like a design grid.
ctx.translateBy(x: 0, y: 1024)
ctx.scaleBy(x: 1, y: -1)

func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
}

// The tile, with the soft shadow every macOS icon has.
let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.28))
ctx.addPath(tile); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tile); ctx.clip()
linear([color(0xFFFFFF), color(0xDCE6FF)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
ctx.restoreGState()

// The play shape: a triangle with round corners, a little right of centre so it looks centred.
func roundedTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    path.move(to: mid)
    path.addArc(tangent1End: b, tangent2End: c, radius: radius)
    path.addArc(tangent1End: c, tangent2End: a, radius: radius)
    path.addArc(tangent1End: a, tangent2End: b, radius: radius)
    path.closeSubpath()
    return path
}
let play = roundedTriangle(CGPoint(x: 280, y: 196), CGPoint(x: 280, y: 836), CGPoint(x: 884, y: 516), radius: 128)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0x0B2A6B, 0.35))
ctx.addPath(play); ctx.setFillColor(color(0x0058CA)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(play); ctx.clip()
linear([color(0x6FA8FF), color(0x0058CA)], from: CGPoint(x: 280, y: 196), to: CGPoint(x: 760, y: 800))
// A soft light along the top edge, the way the system draws depth on its own icons.
linear([color(0xFFFFFF, 0.3), color(0xFFFFFF, 0)], from: CGPoint(x: 512, y: 196), to: CGPoint(x: 512, y: 440))
ctx.restoreGState()

// The note in a light round, as on Android.
let center = CGPoint(x: 470, y: 566)
ctx.addEllipse(in: CGRect(x: center.x - 132, y: center.y - 132, width: 264, height: 264))
ctx.setFillColor(color(0xD6E4FF)); ctx.fillPath()
// The same note as the All Songs tile in the app: the system's music.note, semibold.
let ink = NSColor(srgbRed: 0x0B / 255.0, green: 0x2A / 255.0, blue: 0x6B / 255.0, alpha: 1)
let config = NSImage.SymbolConfiguration(pointSize: 176, weight: .semibold).applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
guard let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(config) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
note.draw(in: CGRect(x: center.x - note.size.width / 2, y: center.y - note.size.height / 2, width: note.size.width, height: note.size.height),
          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
NSGraphicsContext.restoreGraphicsState()

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
