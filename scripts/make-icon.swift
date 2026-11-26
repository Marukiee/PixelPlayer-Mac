// Draws the app icon: the rounded play shape with a note of PixelPlayer on Android, in the Mac app's blue,
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

// The play shape and its note sit a little right of the tile's centre: a play shape's weight lies left of its box
// (centroid at 477 against a box centre of 509.5), so placed by its box it looks too far left.
let nudge: CGFloat = 24
ctx.saveGState()
ctx.translateBy(x: nudge, y: 0)

// The play shape: a triangle with round corners.
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

// The note in a light round, as on Android, a little above the middle of the play shape so it sits in its widest part.
ctx.saveGState()
ctx.translateBy(x: 0, y: -36)
let center = CGPoint(x: 470, y: 566)
ctx.addEllipse(in: CGRect(x: center.x - 132, y: center.y - 132, width: 264, height: 264))
ctx.setFillColor(color(0xD6E4FF)); ctx.fillPath()
let ink = color(0x0B2A6B)
ctx.addEllipse(in: CGRect(x: center.x - 64, y: center.y - 64, width: 128, height: 128))
ctx.setFillColor(ink); ctx.fillPath()
let stem = CGPath(roundedRect: CGRect(x: center.x + 38, y: 330, width: 26, height: center.y - 330 + 8), cornerWidth: 13, cornerHeight: 13, transform: nil)
ctx.addPath(stem); ctx.setFillColor(ink); ctx.fillPath()
let flag = CGMutablePath()
flag.move(to: CGPoint(x: center.x + 50, y: 330))
flag.addCurve(to: CGPoint(x: center.x + 150, y: 410), control1: CGPoint(x: center.x + 120, y: 330), control2: CGPoint(x: center.x + 150, y: 360))
flag.addLine(to: CGPoint(x: center.x + 150, y: 432))
flag.addCurve(to: CGPoint(x: center.x + 50, y: 392), control1: CGPoint(x: center.x + 128, y: 404), control2: CGPoint(x: center.x + 96, y: 392))
flag.closeSubpath()
ctx.addPath(flag); ctx.setFillColor(ink); ctx.fillPath()
ctx.restoreGState()
ctx.restoreGState()

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
