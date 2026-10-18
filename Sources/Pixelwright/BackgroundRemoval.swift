import CoreImage
import PixelwrightCore
import Vision

enum BackgroundRemovalError: LocalizedError {
    case noSubject
    case failed

    var errorDescription: String? {
        switch self {
        case .noSubject: "No foreground subject was found in this image."
        case .failed: "Background removal failed."
        }
    }
}

/// One-click subject cut-out using Apple's on-device foreground segmentation (macOS 14+).
/// Paint.NET has no equivalent; this is Pixelwright's own feature.
enum BackgroundRemoval {
    static func removeBackground(from image: RasterImage) throws -> RasterImage {
        guard let cg = image.makeCGImage() else { throw BackgroundRemovalError.failed }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        try handler.perform([request])

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw BackgroundRemovalError.noSubject
        }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        let ci = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let masked = context.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: space)
        else { throw BackgroundRemovalError.failed }
        return try RasterImage(cgImage: masked)
    }
}
