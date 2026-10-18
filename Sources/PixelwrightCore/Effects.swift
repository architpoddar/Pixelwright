import Foundation

/// Wraps a raw pointer so concurrent line workers can write their own lines.
private struct SharedPointer<T>: @unchecked Sendable {
    let base: UnsafeMutablePointer<T>
}

/// A color adjustment or filter. Effects work on sRGB-encoded color and leave alpha alone
/// (except blur, which blends alpha like color). All amounts are in the units shown in the dialogs.
public enum Effect: Equatable, Sendable {
    /// Both -100...100.
    case brightnessContrast(brightness: Double, contrast: Double)
    /// Hue shift -180...180 degrees; saturation and lightness -100...100.
    case hueSaturation(hue: Double, saturation: Double, lightness: Double)
    /// Radius in pixels.
    case blur(radius: Double)
    /// Amount in percent (0 to 300), radius in pixels.
    case sharpen(amount: Double, radius: Double)
    /// Block size in pixels.
    case pixelate(blockSize: Double)
    case blackAndWhite
    case sepia
    case invertColors

    /// True when applying the effect would change nothing.
    public var isIdentity: Bool {
        switch self {
        case .brightnessContrast(let b, let c): b == 0 && c == 0
        case .hueSaturation(let h, let s, let l): h == 0 && s == 0 && l == 0
        case .blur(let r): Int(r.rounded()) < 1
        case .sharpen(let amount, let r): amount == 0 || Int(r.rounded()) < 1
        case .pixelate(let b): Int(b.rounded()) < 2
        case .blackAndWhite, .sepia, .invertColors: false
        }
    }

    /// The same effect for a copy of the image shrunk by `factor` (1 = full size), so a preview on
    /// a small copy looks like the real thing. Pixel-sized amounts shrink; the rest stay.
    public func scaled(by factor: Double) -> Effect {
        switch self {
        case .blur(let r): .blur(radius: r * factor)
        case .sharpen(let a, let r): .sharpen(amount: a, radius: r * factor)
        case .pixelate(let b): .pixelate(blockSize: b * factor)
        default: self
        }
    }

    public func apply(to image: RasterImage) -> RasterImage {
        guard !isIdentity else { return image }
        switch self {
        case .brightnessContrast(let b, let c): return Self.brightnessContrast(image, brightness: b, contrast: c)
        case .hueSaturation(let h, let s, let l): return Self.hueSaturation(image, hue: h, saturation: s, lightness: l)
        case .blur(let r): return Self.blur(image, radius: Int(r.rounded()))
        case .sharpen(let a, let r): return Self.sharpen(image, amount: a / 100, radius: Int(r.rounded()))
        case .pixelate(let b): return Self.pixelate(image, block: Int(b.rounded()))
        case .blackAndWhite: return Self.mapColor(image) { r, g, b in
            let luma: Double = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
            let y = Self.clamp(luma)
            return (y, y, y)
        }
        case .sepia: return Self.mapColor(image) { r, g, b in
            let dr = Double(r), dg = Double(g), db = Double(b)
            let nr: Double = 0.393 * dr + 0.769 * dg + 0.189 * db
            let ng: Double = 0.349 * dr + 0.686 * dg + 0.168 * db
            let nb: Double = 0.272 * dr + 0.534 * dg + 0.131 * db
            return (Self.clamp(nr), Self.clamp(ng), Self.clamp(nb))
        }
        case .invertColors: return Self.mapColor(image) { r, g, b in (255 - r, 255 - g, 255 - b) }
        }
    }

    // MARK: Per-pixel effects

    private static func clamp(_ v: Double) -> UInt8 { UInt8(min(255, max(0, v.rounded()))) }

    private static func mapColor(_ image: RasterImage, _ f: (UInt8, UInt8, UInt8) -> (UInt8, UInt8, UInt8)) -> RasterImage {
        var out = image
        for p in 0..<(image.width * image.height) {
            let i = p * 4
            let (r, g, b) = f(image.pixels[i], image.pixels[i + 1], image.pixels[i + 2])
            out.pixels[i] = r; out.pixels[i + 1] = g; out.pixels[i + 2] = b
        }
        return out
    }

    private static func brightnessContrast(_ image: RasterImage, brightness: Double, contrast: Double) -> RasterImage {
        let c = max(-100, min(100, contrast)) * 2.55
        let factor = (259 * (c + 255)) / (255 * (259 - c))
        let add = max(-100, min(100, brightness)) * 2.55
        let table = (0..<256).map { v in clamp(factor * (Double(v) - 128) + 128 + add) }
        return mapColor(image) { r, g, b in (table[Int(r)], table[Int(g)], table[Int(b)]) }
    }

    private static func hueSaturation(_ image: RasterImage, hue: Double, saturation: Double, lightness: Double) -> RasterImage {
        let satScale = 1 + max(-100, min(100, saturation)) / 100
        let light = max(-100, min(100, lightness)) / 100
        return mapColor(image) { r, g, b in
            var (h, s, l) = rgbToHSL(Double(r) / 255, Double(g) / 255, Double(b) / 255)
            h = (h + hue / 360).truncatingRemainder(dividingBy: 1)
            if h < 0 { h += 1 }
            s = min(1, max(0, s * satScale))
            l = light > 0 ? l + (1 - l) * light : l * (1 + light)
            let (nr, ng, nb) = hslToRGB(h, s, min(1, max(0, l)))
            return (clamp(nr * 255), clamp(ng * 255), clamp(nb * 255))
        }
    }

    private static func rgbToHSL(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return (0, 0, l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxV == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6
        return (h, s, l)
    }

    private static func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        guard s > 0 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return (channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
    }

    private static func pixelate(_ image: RasterImage, block: Int) -> RasterImage {
        var out = image
        var by = 0
        while by < image.height {
            var bx = 0
            while bx < image.width {
                let x1 = min(image.width, bx + block), y1 = min(image.height, by + block)
                var r = 0, g = 0, b = 0, a = 0
                for y in by..<y1 {
                    for x in bx..<x1 {
                        let i = (y * image.width + x) * 4, alpha = Int(image.pixels[i + 3])
                        r += Int(image.pixels[i]) * alpha; g += Int(image.pixels[i + 1]) * alpha
                        b += Int(image.pixels[i + 2]) * alpha; a += alpha
                    }
                }
                let count = (x1 - bx) * (y1 - by)
                let avgA = (a + count / 2) / count
                let px: RGBA8 = a == 0 ? .clear : RGBA8(
                    r: UInt8((r + a / 2) / a), g: UInt8((g + a / 2) / a), b: UInt8((b + a / 2) / a), a: UInt8(avgA))
                for y in by..<y1 { for x in bx..<x1 { out[x, y] = px } }
                bx += block
            }
            by += block
        }
        return out
    }

    // MARK: Blur and sharpen

    /// Premultiplied RGBA as floats 0...1.
    private static func premultiplied(_ image: RasterImage) -> [Float] {
        var out = [Float](repeating: 0, count: image.pixels.count)
        for p in 0..<(image.width * image.height) {
            let i = p * 4
            let a = Float(image.pixels[i + 3]) / 255
            out[i] = Float(image.pixels[i]) / 255 * a
            out[i + 1] = Float(image.pixels[i + 1]) / 255 * a
            out[i + 2] = Float(image.pixels[i + 2]) / 255 * a
            out[i + 3] = a
        }
        return out
    }

    private static func straight(_ data: [Float], width: Int, height: Int) -> RasterImage {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for p in 0..<(width * height) {
            let i = p * 4
            let a = min(1, max(0, data[i + 3]))
            guard a > 0 else { continue }
            for c in 0..<3 { out[i + c] = UInt8(min(255, max(0, (min(data[i + c], a) / a) * 255 + 0.5))) }
            out[i + 3] = UInt8(min(255, a * 255 + 0.5))
        }
        return RasterImage(width: width, height: height, pixels: out)
    }

    /// Three box blurs per axis, which approximates a Gaussian.
    private static func blurred(_ data: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var data = data
        for _ in 0..<3 {
            blurPass(&data, width: width, height: height, radius: radius, horizontal: true)
            blurPass(&data, width: width, height: height, radius: radius, horizontal: false)
        }
        return data
    }

    private static func blurPass(_ data: inout [Float], width: Int, height: Int, radius: Int, horizontal: Bool) {
        let lines = horizontal ? height : width
        let length = horizontal ? width : height
        let stride = horizontal ? 4 : width * 4
        let lineStart: (Int) -> Int = { horizontal ? $0 * width * 4 : $0 * 4 }
        let window = Float(2 * radius + 1)
        data.withUnsafeMutableBufferPointer { buffer in
            let shared = SharedPointer(base: buffer.baseAddress!)
            DispatchQueue.concurrentPerform(iterations: lines) { line in
                let start = lineStart(line)
                var source = [Float](repeating: 0, count: length * 4)
                for i in 0..<length { for c in 0..<4 { source[i * 4 + c] = shared.base[start + i * stride + c] } }
                for c in 0..<4 {
                    func value(_ i: Int) -> Float { source[min(max(i, 0), length - 1) * 4 + c] }
                    var sum: Float = 0
                    for k in -radius...radius { sum += value(k) }
                    for i in 0..<length {
                        shared.base[start + i * stride + c] = sum / window
                        sum += value(i + radius + 1) - value(i - radius)
                    }
                }
            }
        }
    }

    private static func blur(_ image: RasterImage, radius: Int) -> RasterImage {
        let result = blurred(premultiplied(image), width: image.width, height: image.height, radius: radius)
        return straight(result, width: image.width, height: image.height)
    }

    /// Unsharp mask: adds back `amount` times the difference between the image and its blur.
    private static func sharpen(_ image: RasterImage, amount: Double, radius: Int) -> RasterImage {
        let original = premultiplied(image)
        let soft = blurred(original, width: image.width, height: image.height, radius: radius)
        var result = original
        let k = Float(amount)
        for p in 0..<(image.width * image.height) {
            let i = p * 4
            let a = original[i + 3]
            for c in 0..<3 { result[i + c] = min(a, max(0, original[i + c] + k * (original[i + c] - soft[i + c]))) }
        }
        return straight(result, width: image.width, height: image.height)
    }
}

extension RasterImage {
    /// The image with `effect` applied, only inside `mask` when one is given.
    public func applying(_ effect: Effect, within mask: SelectionMask?) -> RasterImage {
        let full = effect.apply(to: self)
        guard let mask, full != self else { return full }
        precondition(mask.width == width && mask.height == height, "mask size mismatch")
        var out = self
        for p in 0..<(width * height) where mask.flags[p] {
            let i = p * 4
            out.pixels[i] = full.pixels[i]; out.pixels[i + 1] = full.pixels[i + 1]
            out.pixels[i + 2] = full.pixels[i + 2]; out.pixels[i + 3] = full.pixels[i + 3]
        }
        return out
    }

    /// A smaller copy for live previews, plus how much it was shrunk (1 = not at all).
    public func previewCopy(maxDimension: Int) -> (image: RasterImage, factor: Double) {
        let longest = max(width, height)
        guard longest > maxDimension else { return (self, 1) }
        let factor = Double(maxDimension) / Double(longest)
        let small = Resampler.resize(
            self, width: max(1, Int((Double(width) * factor).rounded())),
            height: max(1, Int((Double(height) * factor).rounded())), method: .bilinear, gammaCorrect: false)
        return (small, factor)
    }
}

/// The effects that have a dialog with sliders.
public enum EffectKind: String, CaseIterable, Identifiable, Sendable {
    case brightnessContrast, hueSaturation, blur, sharpen, pixelate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .brightnessContrast: "Brightness / Contrast"
        case .hueSaturation: "Hue / Saturation"
        case .blur: "Blur"
        case .sharpen: "Sharpen"
        case .pixelate: "Pixelate"
        }
    }

    public struct Slider: Sendable {
        public let label: String
        public let range: ClosedRange<Double>
        public let step: Double
        public let defaultValue: Double
        public let unit: String
    }

    public var sliders: [Slider] {
        switch self {
        case .brightnessContrast:
            [Slider(label: "Brightness", range: -100...100, step: 1, defaultValue: 0, unit: ""),
             Slider(label: "Contrast", range: -100...100, step: 1, defaultValue: 0, unit: "")]
        case .hueSaturation:
            [Slider(label: "Hue", range: -180...180, step: 1, defaultValue: 0, unit: "°"),
             Slider(label: "Saturation", range: -100...100, step: 1, defaultValue: 0, unit: ""),
             Slider(label: "Lightness", range: -100...100, step: 1, defaultValue: 0, unit: "")]
        case .blur:
            [Slider(label: "Radius", range: 0...50, step: 1, defaultValue: 4, unit: " px")]
        case .sharpen:
            [Slider(label: "Amount", range: 0...300, step: 5, defaultValue: 100, unit: "%"),
             Slider(label: "Radius", range: 1...20, step: 1, defaultValue: 2, unit: " px")]
        case .pixelate:
            [Slider(label: "Block size", range: 1...100, step: 1, defaultValue: 8, unit: " px")]
        }
    }

    public var defaultValues: [Double] { sliders.map(\.defaultValue) }

    public func effect(values v: [Double]) -> Effect {
        switch self {
        case .brightnessContrast: .brightnessContrast(brightness: v[0], contrast: v[1])
        case .hueSaturation: .hueSaturation(hue: v[0], saturation: v[1], lightness: v[2])
        case .blur: .blur(radius: v[0])
        case .sharpen: .sharpen(amount: v[0], radius: v[1])
        case .pixelate: .pixelate(blockSize: v[0])
        }
    }
}
