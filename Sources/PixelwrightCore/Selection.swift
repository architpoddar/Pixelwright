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

extension RasterImage {
    /// A copy with the selected pixels made fully transparent.
    public func clearingPixels(in mask: SelectionMask) -> RasterImage {
        precondition(mask.width == width && mask.height == height, "mask size mismatch")
        var out = self
        for p in 0..<(width * height) where mask.flags[p] {
            let i = p * 4
            out.pixels[i] = 0
            out.pixels[i + 1] = 0
            out.pixels[i + 2] = 0
            out.pixels[i + 3] = 0
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
