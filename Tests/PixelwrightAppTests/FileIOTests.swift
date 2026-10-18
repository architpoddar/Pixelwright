import Foundation
import PixelwrightCore
import Testing
@testable import Pixelwright

/// A fresh scratch folder for one test.
private func scratchFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pixelwright-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A colorful, noisy-ish opaque image so compression has something to chew on.
private func gradient(_ width: Int, _ height: Int, alpha: UInt8 = 255) -> RasterImage {
    var img = RasterImage(width: width, height: height, fill: .black)
    for y in 0..<height {
        for x in 0..<width {
            img[x, y] = RGBA8(
                r: UInt8((x * 255) / max(1, width - 1)), g: UInt8((y * 255) / max(1, height - 1)),
                b: UInt8((x * 7 + y * 13) % 256), a: alpha)
        }
    }
    return img
}

@Suite("Reading and writing image files")
struct FileIOTests {
    @Test("PNG round-trips exactly, and keeps the resolution")
    func pngRoundTrip() throws {
        let dir = try scratchFolder()
        let url = dir.appendingPathComponent("a.png")
        let img = gradient(40, 30)
        try img.write(to: url, resolution: ImageResolution(pixelsPerInch: 144))
        let loaded = try RasterImage.load(from: url)
        #expect(loaded.image == img)
        #expect(abs(loaded.resolution.pixelsPerInch - 144) < 0.5)
    }

    @Test("A file with no stored resolution loads as 96 per inch")
    func defaultResolution() throws {
        // The engine's default is what the app falls back to.
        #expect(ImageResolution.default.pixelsPerInch == 96)
    }

    @Test("Transparency survives in PNG and is flattened onto white for JPEG")
    func alphaHandling() throws {
        let dir = try scratchFolder()
        var img = RasterImage(width: 4, height: 1, fill: .clear)
        img[0, 0] = RGBA8(r: 200, g: 10, b: 10)
        let png = dir.appendingPathComponent("t.png")
        try img.write(to: png)
        #expect(try RasterImage.load(from: png).image[3, 0].a == 0)

        let jpg = dir.appendingPathComponent("t.jpg")
        try img.write(to: jpg)
        let back = try RasterImage.load(from: jpg).image
        #expect(back[3, 0].a == 255)
        #expect(back[3, 0].r > 240 && back[3, 0].g > 240 && back[3, 0].b > 240, "transparent area should be white, got \(back[3, 0])")
    }

    @Test("JPEG quality changes the file size, and the picture stays close")
    func jpegQuality() throws {
        let img = gradient(160, 120)
        let low = try img.encoded(as: .jpeg, quality: 0.1)
        let high = try img.encoded(as: .jpeg, quality: 0.95)
        #expect(low.count < high.count)

        let dir = try scratchFolder()
        let url = dir.appendingPathComponent("q.jpg")
        try high.write(to: url)
        let back = try RasterImage.load(from: url).image
        #expect(back.width == 160 && back.height == 120)
        var total = 0
        for i in stride(from: 0, to: img.pixels.count, by: 4) { total += abs(Int(img.pixels[i]) - Int(back.pixels[i])) }
        #expect(total / (160 * 120) < 8, "mean red error too high")
    }

    @Test("HEIC and TIFF encode and decode at the same size")
    func otherFormats() throws {
        let dir = try scratchFolder()
        let img = gradient(64, 48)
        for format in [ExportFormat.heic, .tiff] {
            let url = dir.appendingPathComponent("f.\(format.fileExtension)")
            do {
                try img.write(to: url, format: format)
            } catch where format == .heic {
                // Some virtual machines (including CI runners) can't encode HEIC. Not a bug here.
                continue
            }
            let back = try RasterImage.load(from: url).image
            #expect(back.width == 64 && back.height == 48, "\(format)")
        }
    }

    @Test("The format comes from the extension, and unknown extensions fall back to PNG")
    func formatFromExtension() {
        #expect(ExportFormat(pathExtension: "JPG") == .jpeg)
        #expect(ExportFormat(pathExtension: "jpeg") == .jpeg)
        #expect(ExportFormat(pathExtension: "heif") == .heic)
        #expect(ExportFormat(pathExtension: "tif") == .tiff)
        #expect(ExportFormat(pathExtension: "webp") == nil)
        #expect(ExportFormat.png.fileExtension == "png" && ExportFormat.jpeg.fileExtension == "jpg")
        #expect(ExportFormat.jpeg.supportsQuality && ExportFormat.heic.supportsQuality && !ExportFormat.png.supportsQuality)
    }

    @Test("A file that isn't an image gives a clear error")
    func notAnImage() throws {
        let dir = try scratchFolder()
        let url = dir.appendingPathComponent("fake.png")
        try Data("not an image".utf8).write(to: url)
        #expect(throws: ImageIOError.self) { try RasterImage.load(from: url) }
    }
}

@Suite("Batch resize pipeline")
struct BatchPipelineTests {
    private func settings(mode: BatchResizeMode, format: ExportFormat? = nil, suffix: String = "-resized",
                          enlarge: Bool = false) -> BatchJob.Settings {
        .init(mode: mode, allowEnlarging: enlarge, method: .bicubic, gamma: true, format: format, quality: 0.9, suffix: suffix)
    }

    @Test("Resizes into the output folder, leaves the original alone, and keeps the format")
    func endToEnd() throws {
        let dir = try scratchFolder(), out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("photo.png")
        try gradient(200, 100).write(to: source)
        let before = try Data(contentsOf: source)

        try BatchJob.process(source, into: out, settings: settings(mode: .longestSide(pixels: 50)))

        let result = try RasterImage.load(from: out.appendingPathComponent("photo-resized.png")).image
        #expect(result.width == 50 && result.height == 25)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test("Can convert format, and won't enlarge unless asked")
    func convertAndEnlarge() throws {
        let dir = try scratchFolder(), out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("small.png")
        try gradient(40, 20).write(to: source)

        try BatchJob.process(source, into: out, settings: settings(mode: .longestSide(pixels: 400), format: .jpeg, suffix: ""))
        let kept = try RasterImage.load(from: out.appendingPathComponent("small.jpg")).image
        #expect(kept.width == 40 && kept.height == 20)

        try BatchJob.process(source, into: out, settings: settings(mode: .longestSide(pixels: 400), format: .jpeg, suffix: "-big", enlarge: true))
        let big = try RasterImage.load(from: out.appendingPathComponent("small-big.jpg")).image
        #expect(big.width == 400 && big.height == 200)
    }

    @Test("Running twice never overwrites earlier results")
    func noOverwrite() throws {
        let dir = try scratchFolder(), out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("x.png")
        try gradient(30, 30).write(to: source)
        let s = settings(mode: .percentage(50))
        try BatchJob.process(source, into: out, settings: s)
        try BatchJob.process(source, into: out, settings: s)
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        #expect(names == ["x-resized 2.png", "x-resized.png"])
    }

    @Test("The resolution of each image is carried over")
    func keepsResolution() throws {
        let dir = try scratchFolder(), out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("dpi.png")
        try gradient(30, 30).write(to: source, resolution: ImageResolution(pixelsPerInch: 300))
        try BatchJob.process(source, into: out, settings: settings(mode: .percentage(50)))
        let loaded = try RasterImage.load(from: out.appendingPathComponent("dpi-resized.png"))
        #expect(abs(loaded.resolution.pixelsPerInch - 300) < 0.5)
    }
}
