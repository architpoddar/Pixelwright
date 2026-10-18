import Foundation

/// Which pixels are selected: one flag per pixel, row-major.
public struct SelectionMask: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var flags: [Bool]

    public init(width: Int, height: Int, selected: Bool = false) {
        self.width = width
        self.height = height
        self.flags = [Bool](repeating: selected, count: width * height)
    }

    public init(width: Int, height: Int, flags: [Bool]) {
        precondition(flags.count == width * height, "mask size mismatch")
        self.width = width
        self.height = height
        self.flags = flags
    }

    public subscript(x: Int, y: Int) -> Bool {
        get { flags[y * width + x] }
        set { flags[y * width + x] = newValue }
    }

    public var selectedCount: Int { flags.reduce(0) { $0 + ($1 ? 1 : 0) } }
    public var isEmpty: Bool { !flags.contains(true) }

    /// The mask at a different size, by nearest-pixel sampling (used for previews on shrunk copies).
    public func resized(width newWidth: Int, height newHeight: Int) -> SelectionMask {
        var out = SelectionMask(width: newWidth, height: newHeight)
        for y in 0..<newHeight {
            let sy = min(height - 1, y * height / newHeight)
            for x in 0..<newWidth {
                out.flags[y * newWidth + x] = flags[sy * width + min(width - 1, x * width / newWidth)]
            }
        }
        return out
    }

    public func inverted() -> SelectionMask {
        SelectionMask(width: width, height: height, flags: flags.map { !$0 })
    }

    public func union(_ other: SelectionMask) -> SelectionMask {
        precondition(other.width == width && other.height == height, "mask size mismatch")
        return SelectionMask(width: width, height: height, flags: zip(flags, other.flags).map { $0 || $1 })
    }

    public func subtracting(_ other: SelectionMask) -> SelectionMask {
        precondition(other.width == width && other.height == height, "mask size mismatch")
        return SelectionMask(width: width, height: height, flags: zip(flags, other.flags).map { $0 && !$1 })
    }

    /// Grows (positive) or shrinks (negative) the selection by whole pixels, using a
    /// 4-neighborhood per step.
    public func grown(by pixels: Int) -> SelectionMask {
        guard pixels != 0 else { return self }
        var current = pixels > 0 ? self : inverted()
        for _ in 0..<abs(pixels) {
            var next = current
            for y in 0..<height {
                for x in 0..<width where !current[x, y] {
                    if (x > 0 && current[x - 1, y]) || (x < width - 1 && current[x + 1, y])
                        || (y > 0 && current[x, y - 1]) || (y < height - 1 && current[x, y + 1]) {
                        next[x, y] = true
                    }
                }
            }
            current = next
        }
        return pixels > 0 ? current : current.inverted()
    }
}

extension SelectionMask {
    /// How much each pixel is selected, 0 to 1. With `radius` 0 this is just the hard mask; with a
    /// larger radius the edge is feathered: blurred symmetrically so the 50% point stays on the
    /// original boundary. Pixels past the image border count as their nearest edge pixel, so a
    /// selection that touches the border doesn't fade out there.
    public func softCoverage(radius: Int) -> [Float] {
        var data = flags.map { $0 ? Float(1) : 0 }
        guard radius > 0 else { return data }
        // Three box blurs approximate a Gaussian.
        for _ in 0..<3 {
            data = Self.boxBlur(data, width: width, height: height, radius: radius, horizontal: true)
            data = Self.boxBlur(data, width: width, height: height, radius: radius, horizontal: false)
        }
        return data
    }

    private static func boxBlur(_ data: [Float], width: Int, height: Int, radius: Int, horizontal: Bool) -> [Float] {
        var out = data
        let lines = horizontal ? height : width
        let length = horizontal ? width : height
        let window = Float(2 * radius + 1)
        for line in 0..<lines {
            func index(_ i: Int) -> Int { horizontal ? line * width + i : i * width + line }
            func value(_ i: Int) -> Float { data[index(min(max(i, 0), length - 1))] }
            var sum: Float = 0
            for i in -radius...radius { sum += value(i) }
            for i in 0..<length {
                out[index(i)] = sum / window
                sum += value(i + radius + 1) - value(i - radius)
            }
        }
        return out
    }
}

extension RasterImage {
    /// A copy with the selected pixels made transparent. A positive `feather` (in pixels) softens
    /// the boundary: pixels near the edge become partly transparent instead of switching abruptly.
    public func clearingPixels(in mask: SelectionMask, feather: Int = 0) -> RasterImage {
        precondition(mask.width == width && mask.height == height, "mask size mismatch")
        var out = self
        if feather <= 0 {
            for p in 0..<(width * height) where mask.flags[p] {
                let i = p * 4
                out.pixels[i] = 0
                out.pixels[i + 1] = 0
                out.pixels[i + 2] = 0
                out.pixels[i + 3] = 0
            }
            return out
        }
        let coverage = mask.softCoverage(radius: feather)
        for p in 0..<(width * height) where coverage[p] > 0 {
            let i = p * 4
            let keep = 1 - min(1, coverage[p])
            let alpha = UInt8((Float(pixels[i + 3]) * keep).rounded())
            out.pixels[i + 3] = alpha
            if alpha == 0 { out.pixels[i] = 0; out.pixels[i + 1] = 0; out.pixels[i + 2] = 0 }
        }
        return out
    }
}

public enum MagicWandMode: String, CaseIterable, Sendable {
    /// Only pixels connected (up, down, left, right) to the clicked pixel.
    case contiguous
    /// Every pixel in the image that matches, connected or not.
    case global

    public var displayName: String {
        switch self {
        case .contiguous: "Flood fill"
        case .global: "Global"
        }
    }
}

public enum MagicWand {
    /// Selects pixels similar to the pixel at (`x`, `y`).
    ///
    /// Similarity is the distance between the two colors as premultiplied RGBA, so invisible
    /// pixels all count as the same "color". It is compared with the clicked pixel, not with
    /// neighbors, and scaled so 0 means an exact match and 100 matches everything.
    public static func select(
        in image: RasterImage, x: Int, y: Int, tolerance: Double, mode: MagicWandMode
    ) -> SelectionMask {
        var mask = SelectionMask(width: image.width, height: image.height)
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return mask }

        let limit = max(0, min(100, tolerance)) / 100 * maxDistance
        let seed = premultiplied(image, at: y * image.width + x)

        func matches(_ p: Int) -> Bool {
            let c = premultiplied(image, at: p)
            let dr = c.r - seed.r, dg = c.g - seed.g, db = c.b - seed.b, da = c.a - seed.a
            return (dr * dr + dg * dg + db * db + da * da).squareRoot() <= limit + 1e-9
        }

        switch mode {
        case .global:
            for p in 0..<(image.width * image.height) where matches(p) { mask.setFlag(p) }
        case .contiguous:
            var stack = [y * image.width + x]
            mask.setFlag(stack[0])
            while let p = stack.popLast() {
                let px = p % image.width, py = p / image.width
                for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] {
                    guard nx >= 0, ny >= 0, nx < image.width, ny < image.height else { continue }
                    let n = ny * image.width + nx
                    if !mask.flags[n] && matches(n) {
                        mask.setFlag(n)
                        stack.append(n)
                    }
                }
            }
        }
        return mask
    }

    /// Distance between opaque white and fully transparent: sqrt(4) * 255.
    private static let maxDistance = 2 * 255.0

    private static func premultiplied(_ image: RasterImage, at pixel: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let i = pixel * 4
        let a = Double(image.pixels[i + 3])
        let k = a / 255
        return (Double(image.pixels[i]) * k, Double(image.pixels[i + 1]) * k, Double(image.pixels[i + 2]) * k, a)
    }
}

extension SelectionMask {
    fileprivate mutating func setFlag(_ index: Int) { flags[index] = true }
}

// MARK: Shapes

extension SelectionMask {
    /// A rectangular selection, clamped to the image.
    public static func rectangle(width: Int, height: Int, rect: PixelRect) -> SelectionMask {
        var mask = SelectionMask(width: width, height: height)
        let r = rect.intersection(PixelRect(x: 0, y: 0, width: width, height: height))
        guard !r.isEmpty else { return mask }
        for y in r.y..<r.maxY {
            for x in r.x..<r.maxX { mask.flags[y * width + x] = true }
        }
        return mask
    }

    /// A freehand (lasso) selection: the area inside the closed polygon through `points`, given in
    /// pixel coordinates. A pixel is inside when its center is (even-odd rule), so a polygon that
    /// encloses a pixel's center selects it.
    public static func polygon(width: Int, height: Int, points: [(x: Double, y: Double)]) -> SelectionMask {
        var mask = SelectionMask(width: width, height: height)
        guard points.count >= 3 else { return mask }

        for y in 0..<height {
            let cy = Double(y) + 0.5
            var crossings: [Double] = []
            for i in 0..<points.count {
                let a = points[i], b = points[(i + 1) % points.count]
                // Does this edge cross the horizontal line through the pixel centers of row y?
                if (a.y <= cy && b.y > cy) || (b.y <= cy && a.y > cy) {
                    crossings.append(a.x + (cy - a.y) / (b.y - a.y) * (b.x - a.x))
                }
            }
            crossings.sort()
            var i = 0
            while i + 1 < crossings.count {
                // Pixels whose centers (x + 0.5) lie between a pair of crossings.
                let from = max(0, Int((crossings[i] - 0.5).rounded(.up)))
                let to = min(width - 1, Int((crossings[i + 1] - 0.5).rounded(.down)))
                if from <= to { for x in from...to { mask.flags[y * width + x] = true } }
                i += 2
            }
        }
        return mask
    }
}
