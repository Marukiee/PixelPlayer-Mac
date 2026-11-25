import AppKit
// Checks the drawn player icons (UI/Glyphs.swift) against a screenshot of the original: render one with the scripted step
// glyphref:<name>:<W>x<H>:<x>/<y>/<w>/<h>:0 (box from scripts/glyph-bbox.swift), then run this to see both, mine in red.
// overlay.swift <reference> <mine> <out> <scale>: the reference in grey, mine in red on top at 60%, both scaled up.
let a = CommandLine.arguments
let ref = NSImage(contentsOfFile: a[1])!, mine = NSImage(contentsOfFile: a[2])!
let scale = CGFloat(Double(a[4])!)
let refRep = NSBitmapImageRep(data: ref.tiffRepresentation!)!
let w = CGFloat(refRep.pixelsWide) * scale, h = CGFloat(refRep.pixelsHigh) * scale
let out = NSImage(size: NSSize(width: w * 2, height: h))
out.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .none
let left = NSRect(x: 0, y: 0, width: w, height: h), right = NSRect(x: w, y: 0, width: w, height: h)
ref.draw(in: left); ref.draw(in: right)
// Mine, tinted red, over the right copy.
let tinted = NSImage(size: mine.size)
tinted.lockFocus()
mine.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
NSColor.systemRed.set()
NSRect(origin: .zero, size: mine.size).fill(using: .sourceAtop)
tinted.unlockFocus()
tinted.draw(in: right, from: .zero, operation: .sourceOver, fraction: 0.65)
out.unlockFocus()
let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
