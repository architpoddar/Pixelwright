import Foundation

/// The choices offered in the Resize dialog, in dropdown order (spec section 1.1).
///
/// Not yet implemented, pending the open questions in docs/resize-canvas-spec.md:
/// "Bilinear (Low Quality)", "Fant" and "Adaptive (Sharp)".
public enum ResamplingMethod: CaseIterable, Sendable {
    case bicubic          // Catmull-Rom: B = 0, C = 1/2. The default.
    case bicubicSmooth    // Cubic B-spline: B = 1, C = 0. No overshoot, softer.
    case bilinear         // Triangle kernel, widened when shrinking.
    case lanczos          // Lanczos, 3 lobes.
    case nearestNeighbor  // Point sampling. No gamma step.

    public var displayName: String {
        switch self {
        case .bicubic: "Bicubic"
        case .bicubicSmooth: "Bicubic (Smooth)"
        case .bilinear: "Bilinear"
        case .lanczos: "Lanczos"
        case .nearestNeighbor: "Nearest Neighbor"
        }
    }

    /// Gamma correction has no effect when no filtering happens.
    public var supportsGammaCorrection: Bool { self != .nearestNeighbor }

    var kernel: ResamplingKernel? {
        switch self {
        case .bicubic: .cubic(b: 0, c: 0.5)
        case .bicubicSmooth: .cubic(b: 1, c: 0)
        case .bilinear: .triangle
        case .lanczos: .lanczos(lobes: 3)
        case .nearestNeighbor: nil
        }
    }
}

/// A 1-D reconstruction filter. `support` is the half-width in source pixels at scale 1.
struct ResamplingKernel: Sendable {
    let support: Double
    let weight: @Sendable (Double) -> Double

    static let triangle = ResamplingKernel(support: 1) { x in
        let a = abs(x)
        return a < 1 ? 1 - a : 0
    }

    /// Mitchell-Netravali family. (B, C) = (0, 1/2) is Catmull-Rom; (1, 0) is the cubic B-spline.
    static func cubic(b: Double, c: Double) -> ResamplingKernel {
        ResamplingKernel(support: 2) { x in
            let a = abs(x)
            if a < 1 {
                return ((12 - 9 * b - 6 * c) * a * a * a
                    + (-18 + 12 * b + 6 * c) * a * a
                    + (6 - 2 * b)) / 6
            } else if a < 2 {
                return ((-b - 6 * c) * a * a * a
                    + (6 * b + 30 * c) * a * a
                    + (-12 * b - 48 * c) * a
                    + (8 * b + 24 * c)) / 6
            }
            return 0
        }
    }

    static func lanczos(lobes: Int) -> ResamplingKernel {
        let n = Double(lobes)
        return ResamplingKernel(support: n) { x in
            let a = abs(x)
            if a == 0 { return 1 }
            if a >= n { return 0 }
            let px = Double.pi * a
            return n * sin(px) * sin(px / n) / (px * px)
        }
    }
}

/// For each destination pixel along one axis: which source pixels contribute, and how much.
struct AxisWeights {
    var starts: [Int]
    var counts: [Int]
    var offsets: [Int]
    var weights: [Float]

    /// Pixel centers are at (i + 0.5). When shrinking, the kernel is stretched by the shrink
    /// factor so many source pixels are averaged instead of aliased. Weights that fall outside
    /// the source are dropped and the rest renormalized.
    init(sourceSize: Int, destinationSize: Int, kernel: ResamplingKernel) {
        let scale = Double(destinationSize) / Double(sourceSize)
        let filterScale = max(1, 1 / scale)
        let support = kernel.support * filterScale

        starts = []
        counts = []
        offsets = []
        weights = []
        starts.reserveCapacity(destinationSize)
        counts.reserveCapacity(destinationSize)
        offsets.reserveCapacity(destinationSize)

        for i in 0..<destinationSize {
            let center = (Double(i) + 0.5) / scale
            let lo = max(0, Int((center - support - 0.5).rounded(.up)))
            let hi = min(sourceSize - 1, Int((center + support - 0.5).rounded(.down)))

            var taps: [Double] = []
            var sum = 0.0
            if lo <= hi {
                for j in lo...hi {
                    let w = kernel.weight((Double(j) + 0.5 - center) / filterScale)
                    taps.append(w)
                    sum += w
                }
            }

            var start = lo
            if taps.isEmpty || abs(sum) < 1e-12 {
                // Degenerate: fall back to the nearest source pixel.
                start = min(sourceSize - 1, max(0, Int(center.rounded(.down))))
                taps = [1]
                sum = 1
            }

            starts.append(start)
            counts.append(taps.count)
            offsets.append(weights.count)
            for w in taps { weights.append(Float(w / sum)) }
        }
    }
}
