#!/usr/bin/env swift
// Generates Resources/AppIcon.icns from the SF Symbol used in the menu bar ("pencil.tip").
// Usage: swift scripts/make_icon.swift [preview.png]
//   Run from the repo root. Writes Resources/AppIcon.icns (commit it); optionally also a 1024px preview PNG.
import AppKit

let symbolName = "pencil.tip"          // same glyph as the status item (AppDelegate.updateIcon)
let canvas: CGFloat = 1024
let tile: CGFloat = 824                 // Big Sur grid: 824x824 tile centred in 1024 (100px margins)
let corner: CGFloat = 185               // ~22.5% continuous-ish corner radius

func render(size px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)   // draw in 1024-pt space, scaled to px
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let m = (canvas - tile) / 2
    let rect = NSRect(x: m, y: m, width: tile, height: tile)
    let shape = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

    // Soft drop shadow under the tile (standard macOS icon look).
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor.black.withAlphaComponent(0.30)
    sh.shadowBlurRadius = 20
    sh.shadowOffset = NSSize(width: 0, height: -10)
    sh.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Background: warm marker gradient (magenta-red at bottom-left to orange at top-right).
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let grad = NSGradient(colors: [
        NSColor(srgbRed: 0.86, green: 0.10, blue: 0.42, alpha: 1),
        NSColor(srgbRed: 0.97, green: 0.30, blue: 0.27, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.18, alpha: 1),
    ])!
    grad.draw(in: rect, angle: 45)
    // Subtle top highlight for depth.
    let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
    gloss.draw(in: NSRect(x: m, y: m + tile * 0.45, width: tile, height: tile * 0.55), angle: 90 + 180)
    NSGraphicsContext.restoreGraphicsState()

    // Glyph: the SF Symbol in white, fitted into ~64% of the tile and centred.
    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { fatalError("symbol \(symbolName) not found") }
    let target = tile * 0.64
    let s = sym.size
    let k = target / max(s.width, s.height)
    let gw = s.width * k, gh = s.height * k
    let gr = NSRect(x: (canvas - gw) / 2, y: (canvas - gh) / 2, width: gw, height: gh)
    NSGraphicsContext.saveGraphicsState()
    let gs = NSShadow()
    gs.shadowColor = NSColor.black.withAlphaComponent(0.25)
    gs.shadowBlurRadius = 12
    gs.shadowOffset = NSSize(width: 0, height: -6)
    gs.set()
    sym.draw(in: gr)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    png(render(size: base), "\(iconset)/icon_\(base)x\(base).png")
    png(render(size: base * 2), "\(iconset)/icon_\(base)x\(base)@2x.png")
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { fatalError("iconutil failed") }
try? fm.removeItem(atPath: iconset)
if CommandLine.arguments.count > 1 { png(render(size: 1024), CommandLine.arguments[1]) }
print("OK -> Resources/AppIcon.icns")
