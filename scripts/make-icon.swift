#!/usr/bin/env swift
// Generates Pixelwright's app icon and README/social artwork.
//
//   swift scripts/make-icon.swift            (run from the repository root)
//
// Writes Resources/AppIcon.icns, docs/assets/logo.png and docs/assets/social-preview.png.
// The same pixel "P" is drawn in SwiftUI by Sources/Pixelwright/Brand.swift; keep them in sync.
import AppKit

// MARK: Brand

let indigo = NSColor(srgbRed: 0x43 / 255, green: 0x38 / 255, blue: 0xFF / 255, alpha: 1)
let violet = NSColor(srgbRed: 0x7B / 255, green: 0x3F / 255, blue: 0xF2 / 255, alpha: 1)
let coral = NSColor(srgbRed: 0xFF / 255, green: 0x6B / 255, blue: 0x57 / 255, alpha: 1)
let spark = NSColor(srgbRed: 0xFF / 255, green: 0xD2 / 255, blue: 0x3F / 255, alpha: 1)

/// 5 x 7 pixel "P". `S` marks the single spark pixel.
let pattern = [
    "XXXX.",
    "X...S",
    "X...X",
    "XXXX.",
    "X....",
    "X....",
    "X....",
]

// MARK: Drawing

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func withContext(_ rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// The squircle tile with the pixel P, filling `rect`.
func drawTile(in rect: NSRect, shadow: Bool) {
    let radius = rect.width * 0.225
    let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    if shadow {
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.35)
        s.shadowBlurRadius = rect.width * 0.03
        s.shadowOffset = NSSize(width: 0, height: -rect.width * 0.015)
        s.set()
        NSColor.black.setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [indigo, violet, coral], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
        .draw(in: rect, angle: -50)
    // Soft highlight across the top.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The P: 5 x 7 cells with small gaps, centered.
    let cell = rect.width * 0.0947
    let gap = cell * 0.13
    let pitch = cell + gap
    let totalW = pitch * 5 - gap, totalH = pitch * 7 - gap
    let originX = rect.midX - totalW / 2
    let topY = rect.midY + totalH / 2
    for (row, line) in pattern.enumerated() {
        for (col, ch) in line.enumerated() where ch != "." {
            let r = NSRect(x: originX + CGFloat(col) * pitch, y: topY - CGFloat(row + 1) * pitch + gap, width: cell, height: cell)
            let path = NSBezierPath(roundedRect: r, xRadius: cell * 0.2, yRadius: cell * 0.2)
            NSGraphicsContext.saveGraphicsState()
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.25)
            s.shadowBlurRadius = cell * 0.15
            s.shadowOffset = NSSize(width: 0, height: -cell * 0.06)
            s.set()
            (ch == "S" ? spark : NSColor.white).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

func iconImage(pixels: Int) -> NSBitmapImageRep {
    let rep = bitmap(pixels, pixels)
    withContext(rep) {
        let size = CGFloat(pixels)
        let inset = size * 0.098  // macOS icon grid: the tile fills ~80% of the canvas
        drawTile(in: NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset), shadow: true)
    }
    return rep
}

func resized(_ rep: NSBitmapImageRep, to pixels: Int) -> NSBitmapImageRep {
    let out = bitmap(pixels, pixels)
    withContext(out) {
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    }
    return out
}

// MARK: Outputs

let fm = FileManager.default
try? fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try? fm.createDirectory(atPath: "docs/assets", withIntermediateDirectories: true)

let master = iconImage(pixels: 1024)

// .icns via an iconset
let iconset = NSTemporaryDirectory() + "Pixelwright.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(resized(master, to: base), to: "\(iconset)/icon_\(base)x\(base).png")
    writePNG(resized(master, to: base * 2), to: "\(iconset)/icon_\(base)x\(base)@2x.png")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()

writePNG(resized(master, to: 512), to: "docs/assets/logo.png")

// Social preview: 1280 x 640, the size GitHub recommends.
let social = bitmap(1280, 640)
withContext(social) {
    NSGradient(colors: [NSColor(srgbRed: 0x14 / 255, green: 0x10 / 255, blue: 0x3A / 255, alpha: 1),
                        NSColor(srgbRed: 0x2A / 255, green: 0x14 / 255, blue: 0x58 / 255, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: 1280, height: 640), angle: -30)
    drawTile(in: NSRect(x: 110, y: 120, width: 400, height: 400), shadow: true)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    let title = NSMutableAttributedString()
    title.append(NSAttributedString(string: "Pixel", attributes: [
        .font: NSFont.systemFont(ofSize: 112, weight: .light), .foregroundColor: NSColor.white]))
    title.append(NSAttributedString(string: "wright", attributes: [
        .font: NSFont.systemFont(ofSize: 112, weight: .heavy), .foregroundColor: coral]))
    title.draw(at: NSPoint(x: 580, y: 340))
    NSAttributedString(string: "Craft your pixels.", attributes: [
        .font: NSFont.systemFont(ofSize: 48, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85)]).draw(at: NSPoint(x: 586, y: 270))
    NSAttributedString(string: "Resize · Canvas Size · Remove Background · Magic Wand", attributes: [
        .font: NSFont.systemFont(ofSize: 25, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.6)]).draw(at: NSPoint(x: 586, y: 200))
    NSAttributedString(string: "A free, open-source image editor for Mac", attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .regular),
        .foregroundColor: spark]).draw(at: NSPoint(x: 586, y: 150))
}
writePNG(social, to: "docs/assets/social-preview.png")
print("Wrote Resources/AppIcon.icns, docs/assets/logo.png, docs/assets/social-preview.png")
