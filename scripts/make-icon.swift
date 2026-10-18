#!/usr/bin/env swift
// Generates Pixelwright's app icon and README/social artwork.
//
//   swift scripts/make-icon.swift            (run from the repository root)
//
// Writes Resources/AppIcon.icns, docs/assets/logo.png and docs/assets/social-preview.png.
// Synchronized with Sources/Pixelwright/Brand.swift.
import AppKit

// MARK: Brand Colors

let obsidian = NSColor(srgbRed: 0x0B / 255, green: 0x0E / 255, blue: 0x14 / 255, alpha: 1)
let darkSlate = NSColor(srgbRed: 0x1E / 255, green: 0x26 / 255, blue: 0x38 / 255, alpha: 1)
let titanium = NSColor(srgbRed: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255, alpha: 1)
let titaniumShade = NSColor(srgbRed: 0xE2 / 255, green: 0xE8 / 255, blue: 0xF0 / 255, alpha: 1)
let cobalt = NSColor(srgbRed: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255, alpha: 1)
let cobaltDeep = NSColor(srgbRed: 0x1D / 255, green: 0x4E / 255, blue: 0xD8 / 255, alpha: 1)
let mutedSlate = NSColor(srgbRed: 0x8B / 255, green: 0x94 / 255, blue: 0x9E / 255, alpha: 1)

// MARK: Drawing Helpers

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

/// Draws the architectural Precision P glyph and calibration pip.
func drawPrecisionP(in rect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    let glyphW = rect.width * 0.58
    let scale = glyphW / 60.0
    let glyphH = 72.0 * scale
    let originX = rect.midX - glyphW / 2
    let originY = rect.midY - glyphH / 2

    ctx.saveGState()
    // Map to normalized 100x100 SVG space (y pointing down from top-left of glyph at 20, 14)
    ctx.translateBy(x: originX, y: originY + glyphH)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: -20, y: -14)

    // Outer and Inner contour of the P
    let path = CGMutablePath()

    // Outer contour
    path.move(to: CGPoint(x: 24, y: 14))
    path.addLine(to: CGPoint(x: 60, y: 14))
    path.addArc(tangent1End: CGPoint(x: 80, y: 14), tangent2End: CGPoint(x: 80, y: 34), radius: 20)
    path.addArc(tangent1End: CGPoint(x: 80, y: 54), tangent2End: CGPoint(x: 60, y: 54), radius: 20)
    path.addLine(to: CGPoint(x: 36, y: 54))
    path.addLine(to: CGPoint(x: 36, y: 82))
    path.addArc(tangent1End: CGPoint(x: 36, y: 86), tangent2End: CGPoint(x: 32, y: 86), radius: 4)
    path.addLine(to: CGPoint(x: 24, y: 86))
    path.addArc(tangent1End: CGPoint(x: 20, y: 86), tangent2End: CGPoint(x: 20, y: 82), radius: 4)
    path.addLine(to: CGPoint(x: 20, y: 18))
    path.addArc(tangent1End: CGPoint(x: 20, y: 14), tangent2End: CGPoint(x: 24, y: 14), radius: 4)
    path.closeSubpath()

    // Inner counter (Square aperture with subtle rounded corners)
    let counterRect = CGRect(x: 38.5, y: 23, width: 19.5, height: 22)
    path.addRoundedRect(in: counterRect, cornerWidth: 2.5, cornerHeight: 2.5)

    // Shadow under glyph
    ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)

    // Fill glyph body with gradient
    ctx.addPath(path)
    ctx.clip(using: .evenOdd)

    let colors = [titanium.cgColor, titaniumShade.cgColor] as CFArray
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 50, y: 14), end: CGPoint(x: 50, y: 86), options: [])
    }
    ctx.restoreGState()

    // Focal Cobalt Calibration Pip
    ctx.saveGState()
    ctx.translateBy(x: originX, y: originY + glyphH)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: -20, y: -14)

    let pipRect = CGRect(x: 44, y: 31, width: 6, height: 6)
    let pipPath = CGPath(roundedRect: pipRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
    ctx.addPath(pipPath)
    ctx.setFillColor(cobalt.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
}

/// The squircle tile with the precision P, filling `rect`.
func drawTile(in rect: NSRect, shadow: Bool) {
    let radius = rect.width * 0.225
    let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    if shadow {
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.42)
        s.shadowBlurRadius = rect.width * 0.04
        s.shadowOffset = NSSize(width: 0, height: -rect.width * 0.02)
        s.set()
        NSColor.black.setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    // Machined dark slate gradient: Dark Slate (top) to Obsidian (bottom)
    NSGradient(colors: [darkSlate, obsidian], atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: rect, angle: -90)

    // Soft top specular highlight rim
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)

    // Precision P symbol
    drawPrecisionP(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

func iconImage(pixels: Int) -> NSBitmapImageRep {
    let rep = bitmap(pixels, pixels)
    withContext(rep) {
        let size = CGFloat(pixels)
        let inset = size * 0.098  // macOS icon grid: the tile fills ~80.4% of the canvas
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

// Social preview: 1280 x 640, GitHub recommended size.
let social = bitmap(1280, 640)
withContext(social) {
    // Deep slate background with ambient gradient
    NSGradient(colors: [NSColor(srgbRed: 0x0B / 255, green: 0x0E / 255, blue: 0x14 / 255, alpha: 1),
                        NSColor(srgbRed: 0x14 / 255, green: 0x19 / 255, blue: 0x26 / 255, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: 1280, height: 640), angle: -30)

    // Left Icon Tile
    drawTile(in: NSRect(x: 110, y: 120, width: 400, height: 400), shadow: true)

    // Right Typography
    let title = NSAttributedString(string: "Pixelwright", attributes: [
        .font: NSFont.systemFont(ofSize: 108, weight: .bold),
        .foregroundColor: NSColor.white
    ])
    title.draw(at: NSPoint(x: 580, y: 350))

    let tagline = NSAttributedString(string: "Craft your pixels.", attributes: [
        .font: NSFont.systemFont(ofSize: 42, weight: .medium),
        .foregroundColor: cobalt
    ])
    tagline.draw(at: NSPoint(x: 586, y: 280))

    let subtitle = NSAttributedString(string: "The private, focused image editor for Mac", attributes: [
        .font: NSFont.systemFont(ofSize: 26, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85)
    ])
    subtitle.draw(at: NSPoint(x: 586, y: 225))

    let features = NSAttributedString(string: "100% On-Device · Zero Cloud · Originals Untouched", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium),
        .foregroundColor: mutedSlate
    ])
    features.draw(at: NSPoint(x: 586, y: 170))
}
writePNG(social, to: "docs/assets/social-preview.png")
print("Wrote Resources/AppIcon.icns, docs/assets/logo.png, docs/assets/social-preview.png")
