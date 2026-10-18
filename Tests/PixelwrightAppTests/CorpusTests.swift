import Foundation
import PixelwrightCore
import Testing
@testable import Pixelwright

private let corpusPaths: [URL]? = {
    guard let value = ProcessInfo.processInfo.environment["PIXELWRIGHT_CORPUS"], !value.isEmpty else { return nil }
    let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
    let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "bmp", "tif", "tiff"]
    if isDirectory.boolValue {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }.sorted { $0.path < $1.path }
    }
    let lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    return lines.map { URL(fileURLWithPath: $0) }
}()

/// Runs every operation on a folder of real images. Skipped unless you point it at some:
///
///     PIXELWRIGHT_CORPUS=/path/to/folder swift test --filter CorpusTests
///
/// `PIXELWRIGHT_CORPUS` can be a folder or a text file with one image path per line. Nothing is
/// copied or saved anywhere; results are printed. Use it with your own photos before releasing.
@Suite("Real-image corpus", .enabled(if: corpusPaths != nil))
struct CorpusTests {
    private struct Finding: CustomStringConvertible {
        let index: Int, summary: String, problem: String
        var description: String { "#\(index) \(summary): \(problem)" }
    }

    @Test("Every operation works on every image")
    func everythingOnEverything() throws {
        let paths = try #require(corpusPaths)
        var findings: [Finding] = []
        var removed = 0, noSubject = 0
        var slowest: (Double, String) = (0, "")
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("pixelwright-corpus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        for (index, path) in paths.enumerated() {
            let started = Date()
            let ext = path.pathExtension.lowercased()
            func fail(_ summary: String, _ problem: String) { findings.append(Finding(index: index, summary: summary, problem: problem)) }

            // Load
            let loaded: (image: RasterImage, resolution: ImageResolution)
            do { loaded = try RasterImage.load(from: path) } catch { fail(ext, "could not load: \(error)"); continue }
            let image = loaded.image
            let hasAlpha = stride(from: 3, to: image.pixels.count, by: 4).contains { image.pixels[$0] < 255 }
            let summary = "\(ext) \(image.width)x\(image.height)\(hasAlpha ? " alpha" : "")"
            let megapixels = Double(image.width * image.height) / 1e6

            // Resize: every method, down by half, both gamma modes where it matters
            let half = (max(1, image.width / 2), max(1, image.height / 2))
            for method in ResamplingMethod.allCases {
                for gamma in (method.supportsGammaCorrection ? [true, false] : [true]) {
                    let out = Resampler.resize(image, width: half.0, height: half.1, method: method, gammaCorrect: gamma)
                    if out.width != half.0 || out.height != half.1 { fail(summary, "\(method) wrong size") }
                    if hasAlpha {
                        let a0 = meanAlpha(image), a1 = meanAlpha(out)
                        if abs(a0 - a1) > 4 { fail(summary, "\(method) gamma=\(gamma) changed mean alpha \(a0) -> \(a1)") }
                    } else {
                        let c0 = meanColor(image), c1 = meanColor(out)
                        if abs(c0 - c1) > 25 { fail(summary, "\(method) gamma=\(gamma) mean color \(c0) -> \(c1)") }
                    }
                }
            }
            if megapixels <= 2.5 {
                let up = Resampler.resize(image, width: image.width * 2, height: image.height * 2, method: .adaptiveSharp)
                if up.width != image.width * 2 { fail(summary, "upscale wrong size") }
            }
            // Extreme resizes: a sliver and a single pixel
            let sliver = Resampler.resize(image, width: max(1, image.width / 50), height: 3, method: .bicubic)
            if sliver.height != 3 { fail(summary, "sliver wrong size") }
            if Resampler.resize(image, width: 1, height: 1, method: .lanczos).width != 1 { fail(summary, "1x1 failed") }

            // Canvas size: grow and shrink, every anchor corner
            for anchor in [AnchorEdge.topLeft, .middle, .bottomRight] {
                let grown = CanvasSize.resize(image, newWidth: image.width + 31, newHeight: image.height + 17, anchor: anchor, fill: .white)
                let shrunk = CanvasSize.resize(grown, newWidth: image.width, newHeight: image.height, anchor: anchor, fill: .white)
                if shrunk != image { fail(summary, "canvas grow then shrink at \(anchor) didn't give the image back") }
            }

            // Rotate and flip round trips are exact
            var r = image
            for _ in 0..<4 { r = ImageTransform.rotated(r, .clockwise90) }
            if r != image { fail(summary, "four quarter turns changed the image") }
            if ImageTransform.flippedHorizontally(ImageTransform.flippedHorizontally(image)) != image { fail(summary, "double flip H") }
            if ImageTransform.flippedVertically(ImageTransform.flippedVertically(image)) != image { fail(summary, "double flip V") }
            if let cropped = ImageTransform.autoCropped(image), cropped.width > image.width || cropped.height > image.height {
                fail(summary, "auto-crop grew the image")
            }

            // Magic wand
            let cx = image.width / 2, cy = image.height / 2
            if MagicWand.select(in: image, x: cx, y: cy, tolerance: 0, mode: .contiguous).selectedCount < 1 { fail(summary, "wand tol 0 selected nothing") }
            if MagicWand.select(in: image, x: cx, y: cy, tolerance: 100, mode: .global).selectedCount != image.width * image.height {
                fail(summary, "wand tol 100 global didn't select everything")
            }

            // Effects (on a preview-size copy to keep the run quick) and the preview path
            let (small, factor) = image.previewCopy(maxDimension: 600)
            for effect in [Effect.brightnessContrast(brightness: 30, contrast: 30), .hueSaturation(hue: 90, saturation: 20, lightness: 10),
                           .blur(radius: 6), .sharpen(amount: 150, radius: 2), .pixelate(blockSize: 9), .blackAndWhite, .sepia, .invertColors] {
                let out = effect.scaled(by: factor).apply(to: small)
                if out.width != small.width || out.height != small.height { fail(summary, "\(effect) changed size") }
                if hasAlpha, effect != .blur(radius: 6), effect != .pixelate(blockSize: 9), effect != .sharpen(amount: 150, radius: 2) {
                    if meanAlpha(out) != meanAlpha(small) { fail(summary, "\(effect) changed alpha") }
                }
            }
            if Effect.invertColors.apply(to: Effect.invertColors.apply(to: image)) != image { fail(summary, "double invert") }

            // Feathered delete leaves untouched pixels alone
            let mask = SelectionMask.rectangle(width: image.width, height: image.height,
                                               rect: PixelRect(x: 0, y: 0, width: max(1, image.width / 3), height: image.height))
            let feathered = image.clearingPixels(in: mask, feather: 5)
            let farX = image.width - 1, farY = image.height - 1
            if feathered[farX, farY] != image[farX, farY] { fail(summary, "feathered delete touched a far pixel") }

            // Export every format, then read it back
            for format in ExportFormat.allCases {
                do {
                    let data = try image.encoded(as: format, quality: 0.8, resolution: loaded.resolution)
                    let file = tempRoot.appendingPathComponent("\(index).\(format.fileExtension)")
                    try data.write(to: file)
                    let back = try RasterImage.load(from: file).image
                    if back.width != image.width || back.height != image.height { fail(summary, "\(format) export changed size") }
                    if format == .png, !hasAlpha, back != image { fail(summary, "PNG export wasn't lossless") }
                } catch {
                    if format != .heic { fail(summary, "\(format) export failed: \(error)") }
                }
            }

            // The batch pipeline
            do {
                try BatchJob.process(path, into: tempRoot, settings: .init(
                    mode: .longestSide(pixels: 640), allowEnlarging: false, method: .bicubic, gamma: true,
                    format: nil, quality: 0.85, suffix: "-b\(index)"))
            } catch { fail(summary, "batch failed: \(error)") }

            // One-click background removal (Vision)
            do {
                let cut = try BackgroundRemoval.removeBackground(from: image)
                removed += 1
                if cut.width != image.width || cut.height != image.height { fail(summary, "background removal changed size") }
                if !stride(from: 3, to: cut.pixels.count, by: 4).contains(where: { cut.pixels[$0] < 255 }) {
                    fail(summary, "background removal left the image fully opaque")
                }
            } catch BackgroundRemovalError.noSubject {
                noSubject += 1
            } catch { fail(summary, "background removal error: \(error)") }

            let elapsed = Date().timeIntervalSince(started)
            if elapsed > slowest.0 { slowest = (elapsed, summary) }
        }

        print("CORPUS: \(paths.count) images, \(findings.count) problems; background removed on \(removed), no subject on \(noSubject); slowest \(String(format: "%.1f", slowest.0))s (\(slowest.1))")
        for f in findings { print("CORPUS PROBLEM \(f)") }
        #expect(findings.isEmpty, "\(findings.count) problems; see the CORPUS lines in the output")
    }

    private func meanAlpha(_ image: RasterImage) -> Double {
        var total = 0
        for i in stride(from: 3, to: image.pixels.count, by: 4) { total += Int(image.pixels[i]) }
        return Double(total) / Double(image.width * image.height)
    }

    /// Mean of the red, green and blue values over the whole image.
    private func meanColor(_ image: RasterImage) -> Double {
        var total = 0
        for i in 0..<(image.width * image.height) {
            total += Int(image.pixels[i * 4]) + Int(image.pixels[i * 4 + 1]) + Int(image.pixels[i * 4 + 2])
        }
        return Double(total) / Double(image.width * image.height * 3)
    }
}
