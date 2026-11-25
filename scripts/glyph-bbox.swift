import AppKit
// bbox.swift <png> [x0 x1]: the box around the bright pixels (optionally only in columns x0..x1), in pixels.
let a = CommandLine.arguments
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!
let x0 = a.count > 3 ? Int(a[2])! : 0, x1 = a.count > 3 ? Int(a[3])! : rep.pixelsWide - 1
var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
for y in 0..<rep.pixelsHigh { for x in x0...x1 {
    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
    let l = 0.3 * c.redComponent + 0.59 * c.greenComponent + 0.11 * c.blueComponent
    if l > (Double(ProcessInfo.processInfo.environment["T"] ?? "0.45") ?? 0.45) { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
}}
print("\(rep.pixelsWide)x\(rep.pixelsHigh) box x \(minX)...\(maxX) y \(minY)...\(maxY) size \(maxX - minX + 1)x\(maxY - minY + 1)")
