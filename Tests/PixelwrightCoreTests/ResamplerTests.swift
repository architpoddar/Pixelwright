import Testing
@testable import PixelwrightCore

@Suite("Resampling kernels")
struct KernelTests {
    @Test("Catmull-Rom matches known values")
    func catmullRom() {
        let k = ResamplingKernel.cubic(b: 0, c: 0.5)
        #expect(abs(k.weight(0) - 1) < 1e-12)
        #expect(abs(k.weight(1)) < 1e-12)
        #expect(abs(k.weight(2)) < 1e-12)
        #expect(abs(k.weight(0.5) - 0.5625) < 1e-12)
        #expect(k.weight(1.5) < 0) // Catmull-Rom has a negative lobe
        #expect(k.weight(2.5) == 0)
    }

    @Test("Cubic B-spline matches known values and never goes negative")
    func bSpline() {
        let k = ResamplingKernel.cubic(b: 1, c: 0)
        #expect(abs(k.weight(0) - 2.0 / 3.0) < 1e-12)
        #expect(abs(k.weight(1) - 1.0 / 6.0) < 1e-12)
        for i in 0...40 { #expect(k.weight(Double(i) / 20) >= 0) }
    }

    @Test("Lanczos3 and triangle")
    func lanczosAndTriangle() {
        let l = ResamplingKernel.lanczos(lobes: 3)
        #expect(l.weight(0) == 1)
        #expect(abs(l.weight(1)) < 1e-12)
        #expect(l.weight(3) == 0)
        let t = ResamplingKernel.triangle
        #expect(t.weight(0) == 1 && t.weight(0.25) == 0.75 && t.weight(1) == 0)
    }

    @Test("Axis weights are normalized for every method and scale")
    func weightsNormalized() {
        for method in ResamplingMethod.allCases {
            guard let kernel = method.kernel else { continue }
            for (src, dst) in [(100, 37), (37, 100), (64, 64), (3, 1), (1, 9)] {
                let w = AxisWeights(sourceSize: src, destinationSize: dst, kernel: kernel)
                for i in 0..<dst {
                    let sum = (0..<w.counts[i]).reduce(Float(0)) { $0 + w.weights[w.offsets[i] + $1] }
                    #expect(abs(sum - 1) < 1e-4, "\(method) \(src)->\(dst) at \(i)")
                    #expect(w.starts[i] >= 0 && w.starts[i] + w.counts[i] <= src)
                }
            }
        }
    }
}

@Suite("Resampler")
struct ResamplerTests {
    @Test("Same size is returned unchanged")
    func identity() {
        let img = RasterImage(width: 3, height: 3, fill: RGBA8(r: 9, g: 8, b: 7))
        #expect(Resampler.resize(img, width: 3, height: 3) == img)
    }

    @Test("A solid color stays that color, whatever the method, size or gamma mode")
    func solidColorPreserved() {
        let color = RGBA8(r: 200, g: 100, b: 50)
        let img = RasterImage(width: 7, height: 5, fill: color)
        for method in ResamplingMethod.allCases {
            for gamma in [true, false] {
                for (w, h) in [(13, 3), (2, 9), (7, 20), (1, 1)] {
                    let out = Resampler.resize(img, width: w, height: h, method: method, gammaCorrect: gamma)
                    #expect(out.width == w && out.height == h)
                    for y in 0..<h {
                        for x in 0..<w {
                            let p = out[x, y]
                            #expect(
                                abs(Int(p.r) - 200) <= 1 && abs(Int(p.g) - 100) <= 1
                                    && abs(Int(p.b) - 50) <= 1 && p.a == 255,
                                "\(method) gamma=\(gamma) \(w)x\(h) at (\(x),\(y)): \(p)"
                            )
                        }
                    }
                }
            }
        }
    }

    @Test("Nearest neighbor 2x upscale repeats pixels exactly")
    func nearestUpscale() {
        var img = RasterImage(width: 2, height: 2, fill: .black)
        img[0, 0] = RGBA8(r: 1, g: 1, b: 1)
        img[1, 0] = RGBA8(r: 2, g: 2, b: 2)
        img[0, 1] = RGBA8(r: 3, g: 3, b: 3)
        img[1, 1] = RGBA8(r: 4, g: 4, b: 4)
        let out = Resampler.resize(img, width: 4, height: 4, method: .nearestNeighbor)
        for y in 0..<4 {
            for x in 0..<4 {
                #expect(out[x, y] == img[x / 2, y / 2])
            }
        }
    }

    @Test("Gamma correction averages black and white to ~188; without it ~128")
    func gammaAverage() {
        var img = RasterImage(width: 2, height: 1, fill: .black)
        img[1, 0] = .white
        let linear = Resampler.resize(img, width: 1, height: 1, method: .bilinear, gammaCorrect: true)
        let companded = Resampler.resize(img, width: 1, height: 1, method: .bilinear, gammaCorrect: false)
        #expect((187...188).contains(Int(linear[0, 0].r)), "linear light gave \(linear[0, 0].r)")
        #expect((127...128).contains(Int(companded[0, 0].r)), "companded gave \(companded[0, 0].r)")
    }

    @Test("Transparent pixels do not bleed their color into the result")
    func premultipliedAlpha() {
        var img = RasterImage(width: 2, height: 1, fill: .clear)
        img[0, 0] = RGBA8(r: 255, g: 0, b: 0, a: 0)   // invisible red
        img[1, 0] = RGBA8(r: 0, g: 0, b: 255, a: 255) // opaque blue
        for method in [ResamplingMethod.bilinear, .bicubic, .lanczos, .bicubicSmooth] {
            let out = Resampler.resize(img, width: 1, height: 1, method: method)
            #expect(out[0, 0].r == 0, "\(method) leaked red: \(out[0, 0])")
            #expect(out[0, 0].b == 255, "\(method) lost blue: \(out[0, 0])")
            #expect((100...160).contains(Int(out[0, 0].a)), "\(method) alpha \(out[0, 0].a)")
        }
    }

    @Test("Sharp edges don't ring outside the valid range")
    func overshootIsClamped() {
        var img = RasterImage(width: 8, height: 1, fill: .black)
        for x in 4..<8 { img[x, 0] = .white }
        let out = Resampler.resize(img, width: 24, height: 1, method: .lanczos)
        #expect(out.width == 24)
        // Far from the edge stays pure; near the edge stays a valid byte (no wraparound).
        #expect(out[0, 0].r == 0 && out[23, 0].r == 255)
    }

    @Test("Output dimensions are exact for extreme ratios")
    func extremeRatios() {
        let img = RasterImage(width: 50, height: 40, fill: .white)
        let tiny = Resampler.resize(img, width: 1, height: 1, method: .bicubic)
        #expect(tiny.width == 1 && tiny.height == 1 && tiny[0, 0] == .white)
        let wide = Resampler.resize(img, width: 400, height: 3, method: .lanczos)
        #expect(wide.width == 400 && wide.height == 3)
    }
}

@Suite("Size math")
struct SizeMathTests {
    private let original = (width: 1000, height: 600)

    @Test("Rounding is half away from zero")
    func rounding() {
        #expect(SizeMath.roundToPixels(2.5) == 3)
        #expect(SizeMath.roundToPixels(3.5) == 4)
        #expect(SizeMath.roundToPixels(2.4) == 2)
        #expect(SizeMath.roundToPixels(-2.5) == -3)
    }

    @Test("Percentage scales each side independently")
    func percent() {
        let s = SizeMath.size(percent: 50, of: (width: 5, height: 7))
        #expect(s.width == 3 && s.height == 4) // 2.5 -> 3, 3.5 -> 4
        let d = SizeMath.size(percent: 200, of: original)
        #expect(d.width == 2000 && d.height == 1200)
    }

    @Test("Aspect-locked partner values stay unrounded doubles")
    func aspect() {
        let h = SizeMath.height(forWidth: 500, original: original)
        #expect(abs(h - 300) < 1e-9)
        let w = SizeMath.width(forHeight: 100, original: original)
        #expect(abs(w - 166.6666666667) < 1e-6)
    }

    @Test("Limits: pixels 1...262144, resolution 0.01..<2,000,000")
    func limits() {
        #expect(SizeMath.isValid(width: 1, height: 262_144))
        #expect(!SizeMath.isValid(width: 0, height: 10))
        #expect(!SizeMath.isValid(width: 262_145, height: 10))
        #expect(SizeMath.isValid(resolution: 0.01))
        #expect(!SizeMath.isValid(resolution: 0.009))
        #expect(!SizeMath.isValid(resolution: 2_000_000))
        #expect(SizeMath.isValid(resolution: 1_999_999.9))
    }

    @Test("Print size = pixels / resolution (192 px at 96 DPI is 2 in)")
    func printSize() {
        #expect(SizeMath.printSize(pixels: 192, resolution: 96) == 2)
        #expect(SizeMath.pixels(printSize: 2, resolution: 96) == 192)
    }
}
