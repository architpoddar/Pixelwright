import Testing
@testable import PixelwrightCore

private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, a: UInt8 = 255, size: Int = 3) -> RasterImage {
    RasterImage(width: size, height: size, fill: RGBA8(r: r, g: g, b: b, a: a))
}

@Suite("Color adjustments")
struct AdjustmentTests {
    @Test("Brightness and contrast at zero change nothing")
    func identity() {
        let img = solid(10, 130, 250)
        #expect(Effect.brightnessContrast(brightness: 0, contrast: 0).apply(to: img) == img)
        #expect(Effect.brightnessContrast(brightness: 0, contrast: 0).isIdentity)
    }

    @Test("Brightness shifts all channels the same way and clamps")
    func brightness() {
        let up = Effect.brightnessContrast(brightness: 20, contrast: 0).apply(to: solid(100, 100, 100))
        #expect(up[0, 0].r == 151) // 100 + 20 * 2.55
        let clamped = Effect.brightnessContrast(brightness: 100, contrast: 0).apply(to: solid(200, 10, 255))
        #expect(clamped[0, 0].r == 255)
        let down = Effect.brightnessContrast(brightness: -100, contrast: 0).apply(to: solid(100, 10, 255))
        #expect(down[0, 0].r == 0 && down[0, 0].g == 0)
    }

    @Test("Contrast pushes values away from mid-gray and never touches alpha")
    func contrast() {
        let e = Effect.brightnessContrast(brightness: 0, contrast: 40)
        #expect(e.apply(to: solid(128, 128, 128))[0, 0].r == 128)
        #expect(e.apply(to: solid(180, 180, 180))[0, 0].r > 180)
        #expect(e.apply(to: solid(80, 80, 80))[0, 0].r < 80)
        #expect(e.apply(to: solid(180, 180, 180, a: 77))[0, 0].a == 77)
    }

    @Test("Hue 180 turns red into cyan; hue/saturation at zero change nothing")
    func hue() {
        let cyan = Effect.hueSaturation(hue: 180, saturation: 0, lightness: 0).apply(to: solid(255, 0, 0))[0, 0]
        #expect(cyan.r <= 1 && cyan.g >= 254 && cyan.b >= 254)
        let img = solid(12, 99, 200)
        #expect(Effect.hueSaturation(hue: 0, saturation: 0, lightness: 0).apply(to: img) == img)
    }

    @Test("Saturation -100 gives gray; lightness +/-100 gives white or black")
    func saturationLightness() {
        let gray = Effect.hueSaturation(hue: 0, saturation: -100, lightness: 0).apply(to: solid(200, 40, 90))[0, 0]
        #expect(gray.r == gray.g && gray.g == gray.b)
        #expect(Effect.hueSaturation(hue: 0, saturation: 0, lightness: 100).apply(to: solid(200, 40, 90))[0, 0] == .white)
        #expect(Effect.hueSaturation(hue: 0, saturation: 0, lightness: -100).apply(to: solid(200, 40, 90))[0, 0] == .black)
    }

    @Test("Black and white, sepia and invert")
    func simpleEffects() {
        let bw = Effect.blackAndWhite.apply(to: solid(255, 0, 0))[0, 0]
        #expect(bw.r == bw.g && bw.g == bw.b && bw.r == 76) // 0.299 * 255
        #expect(Effect.sepia.apply(to: solid(255, 255, 255))[0, 0] == RGBA8(r: 255, g: 255, b: 239))
        let inv = Effect.invertColors.apply(to: solid(10, 20, 30, a: 128))
        #expect(inv[0, 0] == RGBA8(r: 245, g: 235, b: 225, a: 128))
        #expect(Effect.invertColors.apply(to: inv) == solid(10, 20, 30, a: 128))
    }
}

@Suite("Blur, sharpen, pixelate")
struct FilterTests {
    @Test("Blurring a solid color changes nothing")
    func blurSolid() {
        let img = solid(50, 100, 150, size: 12)
        let out = Effect.blur(radius: 3).apply(to: img)
        for p in 0..<(12 * 12) { #expect(abs(Int(out.pixels[p * 4]) - 50) <= 1 && out.pixels[p * 4 + 3] == 255) }
    }

    @Test("A single bright pixel spreads out symmetrically and keeps about the same total light")
    func blurSpreads() {
        var img = RasterImage(width: 21, height: 21, fill: .black)
        img[10, 10] = .white
        let out = Effect.blur(radius: 2).apply(to: img)
        #expect(out[10, 10].r < 255 && out[10, 10].r > 0)
        #expect(out[8, 10].r > 0 && out[12, 10].r > 0)
        #expect(out[9, 10].r == out[11, 10].r && out[10, 9].r == out[10, 11].r)
        let total = (0..<(21 * 21)).reduce(0) { $0 + Int(out.pixels[$1 * 4]) }
        #expect(abs(total - 255) < 20, "total light \(total)")
    }

    @Test("Radius under one pixel is a no-op")
    func blurNoop() {
        var img = RasterImage(width: 4, height: 4, fill: .black)
        img[1, 1] = .white
        #expect(Effect.blur(radius: 0.4).apply(to: img) == img)
        #expect(Effect.blur(radius: 0).isIdentity)
    }

    @Test("Blurring transparent edges doesn't bleed their hidden color")
    func blurAlpha() {
        var img = RasterImage(width: 9, height: 1, fill: RGBA8(r: 255, g: 0, b: 0, a: 0)) // invisible red
        for x in 4..<9 { img[x, 0] = RGBA8(r: 0, g: 0, b: 255) }
        let out = Effect.blur(radius: 2).apply(to: img)
        #expect(out[4, 0].r == 0, "red leaked into \(out[4, 0])")
    }

    @Test("Sharpening a flat color changes nothing, but overshoots at an edge")
    func sharpen() {
        let flat = solid(120, 120, 120, size: 10)
        let flatOut = Effect.sharpen(amount: 150, radius: 2).apply(to: flat)
        #expect(flatOut[5, 5].r >= 119 && flatOut[5, 5].r <= 121)

        var edge = RasterImage(width: 40, height: 1, fill: RGBA8(r: 100, g: 100, b: 100))
        for x in 20..<40 { edge[x, 0] = RGBA8(r: 150, g: 150, b: 150) }
        let out = Effect.sharpen(amount: 150, radius: 2).apply(to: edge)
        #expect(out[20, 0].r > 150, "bright side should overshoot, got \(out[20, 0].r)")
        #expect(out[19, 0].r < 100, "dark side should undershoot, got \(out[19, 0].r)")
        #expect(out[0, 0].r == 100 && out[39, 0].r == 150) // far from the edge: unchanged
    }

    @Test("Pixelate makes uniform blocks holding the average color")
    func pixelate() {
        var img = RasterImage(width: 4, height: 2, fill: .black)
        img[0, 0] = RGBA8(r: 100, g: 0, b: 0); img[1, 0] = RGBA8(r: 200, g: 0, b: 0)
        img[0, 1] = RGBA8(r: 0, g: 0, b: 0);   img[1, 1] = RGBA8(r: 100, g: 0, b: 0)
        let out = Effect.pixelate(blockSize: 2).apply(to: img)
        #expect(out[0, 0].r == 100 && out[1, 0].r == 100 && out[0, 1].r == 100 && out[1, 1].r == 100)
        #expect(out[2, 0].r == 0 && out[3, 1].r == 0)
        #expect(Effect.pixelate(blockSize: 1).apply(to: img) == img)
    }

    @Test("A block size that doesn't divide the image still covers the edges")
    func pixelateRagged() {
        let img = solid(77, 77, 77, size: 5)
        #expect(Effect.pixelate(blockSize: 3).apply(to: img) == img)
    }
}

@Suite("Applying effects")
struct ApplyingTests {
    @Test("An effect with a selection changes only the selected pixels")
    func withinSelection() {
        let img = solid(100, 100, 100, size: 4)
        var mask = SelectionMask(width: 4, height: 4)
        mask[1, 1] = true
        let out = img.applying(.invertColors, within: mask)
        #expect(out[1, 1].r == 155)
        #expect(out[0, 0].r == 100 && out[3, 3].r == 100)
        #expect(img.applying(.invertColors, within: nil)[0, 0].r == 155)
    }

    @Test("Preview copies shrink big images and report the factor")
    func previews() {
        let big = RasterImage(width: 400, height: 200, fill: .white)
        let (small, factor) = big.previewCopy(maxDimension: 100)
        #expect(small.width == 100 && small.height == 50 && abs(factor - 0.25) < 1e-9)
        let (same, one) = big.previewCopy(maxDimension: 1000)
        #expect(same == big && one == 1)
        #expect(Effect.blur(radius: 8).scaled(by: 0.25) == .blur(radius: 2))
        #expect(Effect.sepia.scaled(by: 0.25) == .sepia)
    }

    @Test("Each dialog's default sliders give a sensible starting effect")
    func kindDefaults() {
        #expect(EffectKind.brightnessContrast.effect(values: EffectKind.brightnessContrast.defaultValues).isIdentity)
        #expect(EffectKind.hueSaturation.effect(values: EffectKind.hueSaturation.defaultValues).isIdentity)
        #expect(!EffectKind.blur.effect(values: EffectKind.blur.defaultValues).isIdentity)
        for kind in EffectKind.allCases {
            #expect(kind.defaultValues.count == kind.sliders.count)
            for s in kind.sliders { #expect(s.range.contains(s.defaultValue)) }
        }
    }
}

@Suite("Effect names")
struct EffectNameTests {
    @Test("Every effect has its own readable name")
    func names() {
        let all: [Effect] = [
            .brightnessContrast(brightness: 1, contrast: 1), .hueSaturation(hue: 1, saturation: 1, lightness: 1),
            .blur(radius: 1), .sharpen(amount: 1, radius: 1), .pixelate(blockSize: 2),
            .blackAndWhite, .sepia, .invertColors,
        ]
        let names = all.map(\.displayName)
        #expect(Set(names).count == all.count)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Effect.blur(radius: 3).displayName == Effect.blur(radius: 9).displayName)
    }
}
