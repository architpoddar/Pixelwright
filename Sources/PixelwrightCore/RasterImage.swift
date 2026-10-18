/// An 8-bit RGBA image: sRGB-encoded color with straight (non-premultiplied) alpha,
/// row-major, 4 bytes per pixel. This is the exchange format at the boundary of the engine;
/// resampling converts to premultiplied float internally.
public struct RasterImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0, "image must be at least 1x1")
        precondition(pixels.count == width * height * 4, "pixel buffer size mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// A solid-color image.
    public init(width: Int, height: Int, fill: RGBA8) {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            data[i * 4] = fill.r
            data[i * 4 + 1] = fill.g
            data[i * 4 + 2] = fill.b
            data[i * 4 + 3] = fill.a
        }
        self.init(width: width, height: height, pixels: data)
    }

    public subscript(x: Int, y: Int) -> RGBA8 {
        get {
            let i = (y * width + x) * 4
            return RGBA8(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2], a: pixels[i + 3])
        }
        set {
            let i = (y * width + x) * 4
            pixels[i] = newValue.r
            pixels[i + 1] = newValue.g
            pixels[i + 2] = newValue.b
            pixels[i + 3] = newValue.a
        }
    }
}

/// One straight-alpha sRGB pixel.
public struct RGBA8: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let clear = RGBA8(r: 0, g: 0, b: 0, a: 0)
    public static let white = RGBA8(r: 255, g: 255, b: 255)
    public static let black = RGBA8(r: 0, g: 0, b: 0)
}
