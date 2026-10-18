import Foundation

/// The choices offered in the Resize dialog, in dropdown order (spec section 1.1).
public enum ResamplingMethod: CaseIterable, Sendable {
    case bicubic             // Catmull-Rom: B = 0, C = 1/2. The default.
    case bicubicSmooth       // Cubic B-spline: B = 1, C = 0. No overshoot, softer.
    case bilinear            // Triangle kernel, widened when shrinking.
    case bilinearLowQuality  // Plain 2-tap bilinear, not widened when shrinking.
    case adaptiveSharp       // Picks a kernel from the scale factor (see `adaptiveKernel`).
    case lanczos             // Lanczos, 3 lobes.
    case fant                // Exact area averaging.
    case nearestNeighbor     // Point sampling. No gamma step.

    public var displayName: String {
        switch self {
        case .bicubic: "Bicubic"
        case .bicubicSmooth: "Bicubic (Smooth)"
        case .bilinear: "Bilinear"
        case .bilinearLowQuality: "Bilinear (Low Quality)"
        case .adaptiveSharp: "Adaptive (Sharp)"
        case .lanczos: "Lanczos"
        case .fant: "Fant"
        case .nearestNeighbor: "Nearest Neighbor"
        }
    }

    /// One plain-language line for the Resize dialog, so people can choose without knowing the jargon.
    public var summary: String {
        switch self {
        case .bicubic: "Smooth and sharp. A good choice for most photos."
        case .bicubicSmooth: "Softer, with no halos around edges."
        case .bilinear: "Soft and quick. Blends neighboring pixels."
        case .bilinearLowQuality: "Fastest, lowest quality. Can look rough when shrinking a lot."
        case .adaptiveSharp: "Picks the best method for how much you shrink or enlarge."
        case .lanczos: "Very sharp detail. Great for enlarging; may show slight halos."
        case .fant: "Averages the area each new pixel covers. Clean when shrinking."
        case .nearestNeighbor: "No smoothing: hard, blocky pixels. Best for pixel art."
        }
    }

    /// Gamma correction has no effect when no filtering happens.
    public var supportsGammaCorrection: Bool { self != .nearestNeighbor }

    /// How the weights for one axis are built for this method.
    func weightStrategy(scaleX: Double, scaleY: Double) -> WeightStrategy? {
        switch self {
        case .bicubic: .kernel(.cubic(b: 0, c: 0.5))
        case .bicubicSmooth: .kernel(.cubic(b: 1, c: 0))
        case .bilinear: .kernel(.triangle)
        case .bilinearLowQuality: .kernel(.triangle, widenWhenShrinking: false)
        case .adaptiveSharp: .kernel(Self.adaptiveKernel(forScale: min(scaleX, scaleY)))
        case .lanczos: .kernel(.lanczos(lobes: 3))
        case .fant: .areaAverage
        case .nearestNeighbor: nil
        }
    }

    /// The kernel behind "Adaptive (Sharp)". `scale` is the smaller of the horizontal and
    /// vertical scale factors (new size / old size):
    /// exactly 1 -> bilinear; below 0.5 -> Lanczos; 0.5 to 4 -> Spline36;
    /// above 4 up to 16 -> Catmull-Rom; above 16 -> interpolating quadratic.
    static func adaptiveKernel(forScale scale: Double) -> ResamplingKernel {
        if scale == 1 { return .triangle }
        if scale < 0.5 { return .lanczos(lobes: 3) }
        if scale > 16 { return .quadratic }
        if scale > 4 { return .cubic(b: 0, c: 0.5) }
        return .spline36
    }
}

enum WeightStrategy {
    case kernel(ResamplingKernel, widenWhenShrinking: Bool = true)
    case areaAverage
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

    /// The standard Spline36 kernel (as used in Panorama Tools and ImageMagick's "Spline"
    /// family): three piecewise cubics over |x| < 3. It passes through zero at every integer
    /// offset, so it keeps the source samples exact while sharpening gently.
    static let spline36 = ResamplingKernel(support: 3) { x in
        let a = abs(x)
        if a < 1 {
            return ((13.0 / 11.0 * a - 453.0 / 209.0) * a - 3.0 / 209.0) * a + 1
        } else if a < 2 {
            let t = a - 1
            return ((-6.0 / 11.0 * t + 270.0 / 209.0) * t - 156.0 / 209.0) * t
        } else if a < 3 {
            let t = a - 2
            return ((1.0 / 11.0 * t - 45.0 / 209.0) * t + 26.0 / 209.0) * t
        }
        return 0
    }

    /// An interpolating quadratic with support 1.5: value 1 at 0, 0 at every integer,
    /// 1/2 at +-0.5. Used for very large enlargements.
    static let quadratic = ResamplingKernel(support: 1.5) { x in
        let a = abs(x)
        if a < 0.5 { return 1 - 2 * a * a }
        if a < 1.5 { return a * a - 2.5 * a + 1.5 }
        return 0
    }
}

/// For each destination pixel along one axis: which source pixels contribute, and how much.
struct AxisWeights {
    var starts: [Int]
    var counts: [Int]
    var offsets: [Int]
    var weights: [Float]

    /// Pixel centers are at (i + 0.5). Weights that fall outside the source are folded into the
    /// nearest edge pixel (edge replication), so the weights for every pixel still sum to 1.
    init(sourceSize: Int, destinationSize: Int, strategy: WeightStrategy) {
        starts = []
        counts = []
        offsets = []
        weights = []
        starts.reserveCapacity(destinationSize)
        counts.reserveCapacity(destinationSize)
        offsets.reserveCapacity(destinationSize)

        let scale = Double(destinationSize) / Double(sourceSize)
        for i in 0..<destinationSize {
            let taps: [(index: Int, weight: Double)]
            switch strategy {
            case .kernel(let kernel, let widen):
                taps = Self.kernelTaps(
                    center: (Double(i) + 0.5) / scale, kernel: kernel,
                    filterScale: widen ? max(1, 1 / scale) : 1)
            case .areaAverage:
                taps = Self.areaTaps(center: (Double(i) + 0.5) / scale, halfWidth: 0.5 / scale)
            }
            append(taps, sourceSize: sourceSize)
        }
    }

    private static func kernelTaps(center: Double, kernel: ResamplingKernel, filterScale: Double)
        -> [(index: Int, weight: Double)]
    {
        let support = kernel.support * filterScale
        let lo = Int((center - support - 0.5).rounded(.up))
        let hi = Int((center + support - 0.5).rounded(.down))
        guard lo <= hi else { return [(Int(center.rounded(.down)), 1)] }
        return (lo...hi).map { j in (j, kernel.weight((Double(j) + 0.5 - center) / filterScale)) }
    }

    /// Fant-style resampling: each output pixel is the exact area-weighted average of the
    /// source pixels (treated as flat squares) that its footprint covers.
    private static func areaTaps(center: Double, halfWidth: Double) -> [(index: Int, weight: Double)] {
        let left = center - halfWidth
        let right = center + halfWidth
        let lo = Int(left.rounded(.down))
        let hi = max(lo, Int(right.rounded(.up)) - 1)
        return (lo...hi).map { j in
            let overlap = min(right, Double(j + 1)) - max(left, Double(j))
            return (j, max(0, overlap))
        }
    }

    private mutating func append(_ taps: [(index: Int, weight: Double)], sourceSize: Int) {
        // Fold out-of-range taps into the edge pixels, then normalize.
        var folded: [Int: Double] = [:]
        var total = 0.0
        for tap in taps {
            folded[min(max(tap.index, 0), sourceSize - 1), default: 0] += tap.weight
            total += tap.weight
        }
        if abs(total) < 1e-12 {
            // Degenerate: use the nearest source pixel.
            let nearest = min(max(taps.first?.index ?? 0, 0), sourceSize - 1)
            folded = [nearest: 1]
            total = 1
        }
        let indices = folded.keys.sorted()
        let first = indices.first!
        let last = indices.last!
        starts.append(first)
        counts.append(last - first + 1)
        offsets.append(weights.count)
        for j in first...last { weights.append(Float((folded[j] ?? 0) / total)) }
    }
}
