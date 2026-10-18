import CoreGraphics
import Foundation
import ImageIO
import PixelwrightCore
import UniformTypeIdentifiers

enum ImageIOError: LocalizedError {
    case cannotRead(URL)
    case cannotCreateImage
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .cannotRead(let url): "Couldn't open \(url.lastPathComponent) as an image."
        case .cannotCreateImage: "Couldn't create an image from the pixel data."
        case .cannotWrite(let url): "Couldn't save \(url.lastPathComponent)."
        }
    }
}

extension RasterImage {
    /// Reads an image file, honoring EXIF orientation, into straight-alpha sRGB RGBA8.
    static func load(from url: URL) throws -> RasterImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageIOError.cannotRead(url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 32_768,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageIOError.cannotRead(url)
        }
        return try RasterImage(cgImage: cg)
    }

    init(cgImage: CGImage) throws {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { throw ImageIOError.cannotCreateImage }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { throw ImageIOError.cannotCreateImage }

        // The context holds premultiplied bytes; the engine wants straight alpha.
        let src = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for p in 0..<(w * h) {
            let i = p * 4
            let a = Int(src[i + 3])
            if a == 255 {
                out[i] = src[i]; out[i + 1] = src[i + 1]; out[i + 2] = src[i + 2]; out[i + 3] = 255
            } else if a > 0 {
                out[i] = UInt8(min(255, (Int(src[i]) * 255 + a / 2) / a))
                out[i + 1] = UInt8(min(255, (Int(src[i + 1]) * 255 + a / 2) / a))
                out[i + 2] = UInt8(min(255, (Int(src[i + 2]) * 255 + a / 2) / a))
                out[i + 3] = UInt8(a)
            }
        }
        self.init(width: w, height: h, pixels: out)
    }

    /// A CGImage that references straight-alpha RGBA bytes (a copy of the pixels).
    func makeCGImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    func write(to url: URL) throws {
        let type: UTType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": type = .jpeg
        case "heic": type = .heic
        case "tif", "tiff": type = .tiff
        default: type = .png
        }
        // JPEG has no alpha: flatten onto white so transparent areas don't turn black.
        let source = type == .jpeg ? flattened(onto: .white) : self
        guard let cg = source.makeCGImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw ImageIOError.cannotWrite(url) }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw ImageIOError.cannotWrite(url) }
    }

    private func flattened(onto background: RGBA8) -> RasterImage {
        var out = self
        for p in 0..<(width * height) {
            let i = p * 4
            let a = Int(pixels[i + 3])
            for c in 0..<3 {
                let fg = Int(pixels[i + c]), bg = Int([background.r, background.g, background.b][c])
                out.pixels[i + c] = UInt8((fg * a + bg * (255 - a) + 127) / 255)
            }
            out.pixels[i + 3] = 255
        }
        return out
    }
}
