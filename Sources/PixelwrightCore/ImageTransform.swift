import Foundation

/// A rectangle of whole pixels. `x`, `y` is the top-left corner.
public struct PixelRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }

    /// The overlap of two rectangles (empty if they don't touch).
    public func intersection(_ other: PixelRect) -> PixelRect {
        let x0 = max(x, other.x), y0 = max(y, other.y)
        let x1 = min(maxX, other.maxX), y1 = min(maxY, other.maxY)
        return PixelRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}

public enum Rotation: Sendable {
    case clockwise90
    case counterclockwise90
    case half
}

/// Pixel-exact transforms: no resampling, so nothing is lost.
public enum ImageTransform {
    public static func rotated(_ image: RasterImage, _ rotation: Rotation) -> RasterImage {
        let w = image.width, h = image.height
        let swaps = rotation != .half
        let outW = swaps ? h : w, outH = swaps ? w : h
        var out = [UInt8](repeating: 0, count: image.pixels.count)
        image.pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    for x in 0..<w {
                        let (nx, ny): (Int, Int)
                        switch rotation {
                        case .clockwise90: (nx, ny) = (h - 1 - y, x)
                        case .counterclockwise90: (nx, ny) = (y, w - 1 - x)
                        case .half: (nx, ny) = (w - 1 - x, h - 1 - y)
                        }
                        let s = (y * w + x) * 4, d = (ny * outW + nx) * 4
                        dst[d] = src[s]; dst[d + 1] = src[s + 1]; dst[d + 2] = src[s + 2]; dst[d + 3] = src[s + 3]
                    }
                }
            }
        }
        return RasterImage(width: outW, height: outH, pixels: out)
    }

    public static func flippedHorizontally(_ image: RasterImage) -> RasterImage {
        let w = image.width
        var out = image
        for y in 0..<image.height {
            for x in 0..<w {
                let s = (y * w + x) * 4, d = (y * w + (w - 1 - x)) * 4
                out.pixels[d] = image.pixels[s]; out.pixels[d + 1] = image.pixels[s + 1]
                out.pixels[d + 2] = image.pixels[s + 2]; out.pixels[d + 3] = image.pixels[s + 3]
            }
        }
        return out
    }

    public static func flippedVertically(_ image: RasterImage) -> RasterImage {
        let rowBytes = image.width * 4
        var out = image
        for y in 0..<image.height {
            let s = y * rowBytes, d = (image.height - 1 - y) * rowBytes
            out.pixels.replaceSubrange(d..<(d + rowBytes), with: image.pixels[s..<(s + rowBytes)])
        }
        return out
    }

    /// The part of the image inside `rect` (clamped to the image), or nil if nothing is left.
    public static func cropped(_ image: RasterImage, to rect: PixelRect) -> RasterImage? {
        let r = rect.intersection(PixelRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !r.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: r.width * r.height * 4)
        let rowBytes = r.width * 4
        for y in 0..<r.height {
            let s = ((r.y + y) * image.width + r.x) * 4
            out.replaceSubrange((y * rowBytes)..<((y + 1) * rowBytes), with: image.pixels[s..<(s + rowBytes)])
        }
        return RasterImage(width: r.width, height: r.height, pixels: out)
    }

    /// The smallest rectangle containing every pixel that isn't fully transparent,
    /// or nil if the whole image is transparent.
    public static func opaqueBounds(_ image: RasterImage) -> PixelRect? {
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where image.pixels[(y * image.width + x) * 4 + 3] != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                maxY = y
            }
        }
        guard maxX >= 0 else { return nil }
        return PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Trims fully transparent borders. Nil if the image is entirely transparent.
    public static func autoCropped(_ image: RasterImage) -> RasterImage? {
        opaqueBounds(image).flatMap { cropped(image, to: $0) }
    }
}

extension SelectionMask {
    /// The smallest rectangle containing every selected pixel, or nil if nothing is selected.
    public var bounds: PixelRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where flags[y * width + x] {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                maxY = y
            }
        }
        guard maxX >= 0 else { return nil }
        return PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// True if the selection fills its whole bounding rectangle.
    public var isRectangular: Bool {
        guard let b = bounds else { return false }
        return selectedCount == b.width * b.height
    }
}

extension RasterImage {
    /// Crops to the selection's bounds. Pixels inside the bounds but outside the selection become
    /// transparent, so a non-rectangular selection cuts out just its shape.
    public func croppedToSelection(_ mask: SelectionMask) -> RasterImage? {
        guard let b = mask.bounds,
              let cropped = ImageTransform.cropped(self, to: b) else { return nil }
        if mask.isRectangular { return cropped }
        var out = cropped
        for y in 0..<b.height {
            for x in 0..<b.width where !mask[b.x + x, b.y + y] {
                out[x, y] = .clear
            }
        }
        return out
    }
}
