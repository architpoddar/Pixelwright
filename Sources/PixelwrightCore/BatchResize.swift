import Foundation

/// How batch resize decides each image's new size.
public enum BatchResizeMode: Equatable, Sendable {
    /// Scale so the longer side is `pixels` long, keeping the shape.
    case longestSide(pixels: Int)
    /// Scale to fit inside a box, keeping the shape. A nil limit means "no limit" on that side.
    case fitWithin(maxWidth: Int?, maxHeight: Int?)
    /// Scale both sides by a percentage.
    case percentage(Double)

    /// The new size for an image of `width` x `height`. With `allowEnlarging` false, an image that
    /// is already smaller than the target is left at its own size. The result is never smaller
    /// than 1 x 1 and never larger than the engine's pixel limit.
    public func targetSize(width: Int, height: Int, allowEnlarging: Bool) -> (width: Int, height: Int) {
        var scale: Double
        switch self {
        case .longestSide(let pixels):
            scale = Double(pixels) / Double(max(width, height))
        case .fitWithin(let maxW, let maxH):
            var candidates: [Double] = []
            if let maxW { candidates.append(Double(maxW) / Double(width)) }
            if let maxH { candidates.append(Double(maxH) / Double(height)) }
            scale = candidates.min() ?? 1
        case .percentage(let percent):
            scale = percent / 100
        }
        if !allowEnlarging { scale = min(scale, 1) }
        let limit = Double(SizeMath.pixelRange.upperBound)
        let w = min(limit, max(1, (Double(width) * scale).rounded(.toNearestOrAwayFromZero)))
        let h = min(limit, max(1, (Double(height) * scale).rounded(.toNearestOrAwayFromZero)))
        return (Int(w), Int(h))
    }

    /// False if the settings can't produce a sensible size (zero or negative limits).
    public var isValid: Bool {
        switch self {
        case .longestSide(let p): p > 0
        case .fitWithin(let w, let h): (w ?? 1) > 0 && (h ?? 1) > 0 && (w != nil || h != nil)
        case .percentage(let p): p > 0
        }
    }
}

public enum BatchNaming {
    /// "photo.jpg" with suffix "-small" and extension "png" becomes "photo-small.png".
    public static func outputName(for original: String, suffix: String, fileExtension: String) -> String {
        let base = (original as NSString).deletingPathExtension
        return "\(base)\(suffix).\(fileExtension)"
    }

    /// Picks a name that isn't taken by adding " 2", " 3", ... before the extension.
    public static func uniqueName(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !exists(candidate) { return candidate }
            n += 1
        }
    }
}

public enum SaveNaming {
    /// The name offered when saving a copy: "photo.jpg" becomes "photo edited.png" (or the given
    /// extension). It never matches an existing file, so the default can't overwrite anything.
    /// `original` is nil for images that didn't come from a file (the clipboard, say).
    public static func suggestedCopyName(original: String?, fileExtension: String, exists: (String) -> Bool) -> String {
        let base = original.map { ($0 as NSString).deletingPathExtension } ?? "Untitled"
        let cleaned = base.isEmpty ? "Untitled" : base
        let name = original == nil ? "\(cleaned).\(fileExtension)" : "\(cleaned) edited.\(fileExtension)"
        return BatchNaming.uniqueName(name, exists: exists)
    }
}
