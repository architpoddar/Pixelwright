import Foundation

/// The arithmetic behind the Resize / Canvas Size dialogs (spec section 1.2).
public enum SizeMath {
    /// Largest and smallest allowed pixel size per side.
    public static let pixelRange = 1...262_144
    /// Allowed resolution (pixels per unit): at least 0.01, below 2,000,000.
    public static let resolutionRange: Range<Double> = 0.01..<2_000_000

    /// Rounds to nearest, ties away from zero, then clamps to Int range.
    public static func roundToPixels(_ value: Double) -> Int {
        let r = value.rounded(.toNearestOrAwayFromZero)
        return Int(min(max(r, Double(Int32.min)), Double(Int32.max)))
    }

    public static func isValid(width: Int, height: Int) -> Bool {
        pixelRange.contains(width) && pixelRange.contains(height)
    }

    public static func isValid(resolution: Double) -> Bool {
        resolutionRange.contains(resolution)
    }

    /// "By percentage": each side is scaled and rounded independently.
    public static func size(percent: Double, of original: (width: Int, height: Int)) -> (width: Int, height: Int) {
        (roundToPixels(Double(original.width) * percent / 100),
         roundToPixels(Double(original.height) * percent / 100))
    }

    /// Aspect-locked partner values. These stay as doubles; round only when reading pixels.
    public static func height(forWidth width: Double, original: (width: Int, height: Int)) -> Double {
        width / (Double(original.width) / Double(original.height))
    }

    public static func width(forHeight height: Double, original: (width: Int, height: Int)) -> Double {
        height * (Double(original.width) / Double(original.height))
    }

    /// Print size in the chosen unit: pixels / resolution (e.g. 192 px at 96 DPI = 2 in).
    public static func printSize(pixels: Double, resolution: Double) -> Double {
        pixels / resolution
    }

    public static func pixels(printSize: Double, resolution: Double) -> Double {
        printSize * resolution
    }
}
