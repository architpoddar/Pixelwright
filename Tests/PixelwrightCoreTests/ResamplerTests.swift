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
            for (src, dst) in [(100, 37), (37, 100), (64, 64), (3, 1), (1, 9), (10, 400), (400, 10)] {
                let scale = Double(dst) / Double(src)
                guard let strategy = method.weightStrategy(scaleX: scale, scaleY: scale) else { continue }
                let w = AxisWeights(sourceSize: src, destinationSize: dst, strategy: strategy)
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

@Suite("Additional resampling modes")
struct AdditionalModeTests {
    @Test("Spline36 hits its defining values and is a partition of unity")
    func spline36() {
        let k = ResamplingKernel.spline36
        #expect(abs(k.weight(0) - 1) < 1e-12)
        for n in 1...3 { #expect(abs(k.weight(Double(n))) < 1e-12, "k(\(n))") }
        #expect(k.weight(3.5) == 0)
        // Samples of a kernel with integer-spaced shifts must sum to 1 for any offset.
        for f in stride(from: 0.0, to: 1.0, by: 0.1) {
            let sum = (-3...3).reduce(0.0) { $0 + k.weight(f - Double($1)) }
            #expect(abs(sum - 1) < 1e-9, "offset \(f): \(sum)")
        }
    }

    @Test("Quadratic interpolates: 1 at 0, 0 at integers, 1/2 at half steps")
    func quadratic() {
        let k = ResamplingKernel.quadratic
        #expect(k.weight(0) == 1)
        #expect(abs(k.weight(1)) < 1e-12)
        #expect(abs(k.weight(0.5) - 0.5) < 1e-12)
        #expect(abs(k.weight(1.5)) < 1e-12)
        for f in stride(from: 0.0, to: 1.0, by: 0.125) {
            let sum = (-2...2).reduce(0.0) { $0 + k.weight(f - Double($1)) }
            #expect(abs(sum - 1) < 1e-9, "offset \(f): \(sum)")
        }
    }

    @Test("Adaptive picks its kernel from the scale factor")
    func adaptiveSelection() {
        func probe(_ scale: Double) -> (support: Double, mid: Double) {
            let k = ResamplingMethod.adaptiveKernel(forScale: scale)
            return (k.support, k.weight(0.5))
        }
        #expect(probe(1).support == 1)       // bilinear
        #expect(probe(0.4).support == 3)     // Lanczos
        #expect(probe(0.5).support == 3)     // Spline36 starts at exactly 0.5
        #expect(probe(2).support == 3)       // Spline36
        #expect(probe(4).support == 3)       // Spline36 still includes 4
        #expect(probe(5).support == 2)       // Catmull-Rom
        #expect(probe(16).support == 2)      // Catmull-Rom still includes 16
        #expect(probe(20).support == 1.5)    // quadratic
        // Lanczos and Spline36 both have support 3, so tell them apart by value.
        #expect(abs(probe(0.4).mid - 0.6079271018540267) < 1e-9)  // Lanczos3 at 0.5
        #expect(abs(probe(2).mid - ResamplingKernel.spline36.weight(0.5)) < 1e-12)
    }

    @Test("Fant is an exact area average: 4 -> 2 averages pairs, 3 -> 1 averages all")
    func fantAverages() {
        var img = RasterImage(width: 4, height: 1, fill: .black)
        for (x, v) in [0, 100, 200, 40].enumerated() { img[x, 0] = RGBA8(r: UInt8(v), g: UInt8(v), b: UInt8(v)) }
        let half = Resampler.resize(img, width: 2, height: 1, method: .fant, gammaCorrect: false)
        #expect(half[0, 0].r == 50 && half[1, 0].r == 120)

        var three = RasterImage(width: 3, height: 1, fill: .black)
        for (x, v) in [30, 60, 120].enumerated() { three[x, 0] = RGBA8(r: UInt8(v), g: UInt8(v), b: UInt8(v)) }
        let one = Resampler.resize(three, width: 1, height: 1, method: .fant, gammaCorrect: false)
        #expect(one[0, 0].r == 70)
    }

    @Test("Fant weights split pixels fractionally when the ratio isn't whole (3 -> 2)")
    func fantFractional() {
        let w = AxisWeights(sourceSize: 3, destinationSize: 2, strategy: .areaAverage)
        // Output 0 covers source [0, 1.5): all of pixel 0 and half of pixel 1.
        #expect(w.starts[0] == 0 && w.counts[0] == 2)
        #expect(abs(w.weights[w.offsets[0]] - 2.0 / 3.0) < 1e-6)
        #expect(abs(w.weights[w.offsets[0] + 1] - 1.0 / 3.0) < 1e-6)
    }

    @Test("Low-quality bilinear only ever uses two source pixels, even when shrinking a lot")
    func lowQualityIsTwoTap() {
        let scale = 2.0 / 12.0
        let strategy = ResamplingMethod.bilinearLowQuality.weightStrategy(scaleX: scale, scaleY: scale)!
        let w = AxisWeights(sourceSize: 12, destinationSize: 2, strategy: strategy)
        for i in 0..<2 { #expect(w.counts[i] <= 2) }
        // Proper bilinear averages many pixels when shrinking.
        let full = ResamplingMethod.bilinear.weightStrategy(scaleX: scale, scaleY: scale)!
        let wide = AxisWeights(sourceSize: 12, destinationSize: 2, strategy: full)
        #expect(wide.counts[0] > 2)
    }

    @Test("Low-quality bilinear picks exact pixels on a ramp where area averaging would blur")
    func lowQualityRamp() {
        var img = RasterImage(width: 6, height: 1, fill: .black)
        for x in 0..<6 { let v = UInt8(x * 40); img[x, 0] = RGBA8(r: v, g: v, b: v) }
        // 6 -> 2: output centers map to source positions 1.0 and 4.0 -> pixels 1 and 4 exactly.
        let lq = Resampler.resize(img, width: 2, height: 1, method: .bilinearLowQuality, gammaCorrect: false)
        #expect(lq[0, 0].r == 40 && lq[1, 0].r == 160)
    }

    @Test("Edge pixels replicate: weights past the border fold onto the edge pixel")
    func edgeReplication() {
        // Catmull-Rom, 4 -> 8. Output 0 center = 0.25 -> window reaches left of pixel 0.
        let strategy = ResamplingMethod.bicubic.weightStrategy(scaleX: 2, scaleY: 2)!
        let w = AxisWeights(sourceSize: 4, destinationSize: 8, strategy: strategy)
        #expect(w.starts[0] == 0)
        let k = ResamplingKernel.cubic(b: 0, c: 0.5)
        let center = 0.25
        let taps = (-2...2).map { (j: $0, w: k.weight(Double($0) + 0.5 - center)) }
        let total = taps.reduce(0.0) { $0 + $1.w }
        let edge = taps.filter { $0.j <= 0 }.reduce(0.0) { $0 + $1.w } / total
        #expect(abs(Double(w.weights[w.offsets[0]]) - edge) < 1e-6)
    }

    @Test("Every method keeps a solid color solid, including the new ones")
    func newModesPreserveSolid() {
        let img = RasterImage(width: 9, height: 7, fill: RGBA8(r: 12, g: 200, b: 99))
        for method in [ResamplingMethod.bilinearLowQuality, .adaptiveSharp, .fant] {
            for (w, h) in [(3, 2), (30, 21), (400, 5)] {
                let out = Resampler.resize(img, width: w, height: h, method: method)
                for y in 0..<h { for x in 0..<w {
                    let p = out[x, y]
                    #expect(abs(Int(p.r) - 12) <= 1 && abs(Int(p.g) - 200) <= 1 && abs(Int(p.b) - 99) <= 1 && p.a == 255,
                            "\(method) \(w)x\(h) (\(x),\(y)): \(p)")
                } }
            }
        }
    }
}

@Suite("Resize dialog contents")
struct DialogContentsTests {
    @Test("The dropdown lists the eight methods in Paint.NET's order")
    func dropdownOrder() {
        #expect(ResamplingMethod.allCases.map(\.displayName) == [
            "Bicubic", "Bicubic (Smooth)", "Bilinear", "Bilinear (Low Quality)",
            "Adaptive (Sharp)", "Lanczos", "Fant", "Nearest Neighbor",
        ])
        #expect(ResamplingMethod.allCases.first == .bicubic) // the default
    }

    @Test("Only Nearest Neighbor ignores gamma correction")
    func gammaSupport() {
        for method in ResamplingMethod.allCases {
            #expect(method.supportsGammaCorrection == (method != .nearestNeighbor))
        }
    }
}
