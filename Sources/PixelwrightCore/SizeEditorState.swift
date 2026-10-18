import Foundation

/// Physical units for print size and resolution.
public enum MeasurementUnit: String, CaseIterable, Sendable {
    case inches
    case centimeters

    public var displayName: String {
        switch self {
        case .inches: "inches"
        case .centimeters: "centimeters"
        }
    }

    /// Short label for resolution: "pixels/inch" or "pixels/cm".
    public var resolutionLabel: String {
        switch self {
        case .inches: "pixels/inch"
        case .centimeters: "pixels/cm"
        }
    }

    static let centimetersPerInch = 2.54
}

/// How many pixels fit in one physical unit.
public struct ImageResolution: Equatable, Sendable {
    public var pixelsPerUnit: Double
    public var unit: MeasurementUnit

    public init(pixelsPerUnit: Double, unit: MeasurementUnit) {
        self.pixelsPerUnit = pixelsPerUnit
        self.unit = unit
    }

    /// The default for images that don't say: 96 pixels per inch.
    public static let `default` = ImageResolution(pixelsPerUnit: 96, unit: .inches)

    public var pixelsPerInch: Double {
        switch unit {
        case .inches: pixelsPerUnit
        case .centimeters: pixelsPerUnit * MeasurementUnit.centimetersPerInch
        }
    }

    public init(pixelsPerInch: Double) {
        self.init(pixelsPerUnit: pixelsPerInch, unit: .inches)
    }

    public func converted(to newUnit: MeasurementUnit) -> ImageResolution {
        guard newUnit != unit else { return self }
        switch newUnit {
        case .inches: return ImageResolution(pixelsPerUnit: pixelsPerInch, unit: .inches)
        case .centimeters:
            return ImageResolution(pixelsPerUnit: pixelsPerInch / MeasurementUnit.centimetersPerInch, unit: .centimeters)
        }
    }
}

/// The state behind the Resize and Canvas Size dialogs: pixel size, print size, resolution and
/// percentage, kept consistent with each other (spec section 1.2).
///
/// Print size (in the chosen unit) is the stored truth, as doubles. Pixel size is derived as
/// print size x resolution and rounded only when read. Changing the resolution keeps the print
/// size and so changes the pixel size; changing the pixel size changes the print size.
public struct SizeEditorState: Equatable, Sendable {
    public let originalWidth: Int
    public let originalHeight: Int
    public private(set) var printWidth: Double
    public private(set) var printHeight: Double
    public private(set) var resolution: ImageResolution
    public var keepAspect: Bool

    public init(originalWidth: Int, originalHeight: Int, resolution: ImageResolution, keepAspect: Bool) {
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.resolution = resolution
        self.keepAspect = keepAspect
        self.printWidth = Double(originalWidth) / resolution.pixelsPerUnit
        self.printHeight = Double(originalHeight) / resolution.pixelsPerUnit
    }

    // MARK: Derived values

    public var pixelWidth: Int { SizeMath.roundToPixels(printWidth * resolution.pixelsPerUnit) }
    public var pixelHeight: Int { SizeMath.roundToPixels(printHeight * resolution.pixelsPerUnit) }
    public var unit: MeasurementUnit { resolution.unit }

    /// New size as a percentage of the original width.
    public var percent: Double { printWidth * resolution.pixelsPerUnit / Double(originalWidth) * 100 }

    /// True when pixel size, print size and resolution are all acceptable.
    public var isValid: Bool {
        SizeMath.isValid(width: pixelWidth, height: pixelHeight)
            && SizeMath.isValid(resolution: resolution.pixelsPerUnit)
            && printWidth > 0 && printHeight > 0
    }

    private var originalSize: (width: Int, height: Int) { (originalWidth, originalHeight) }

    // MARK: Edits

    public mutating func setPixelWidth(_ pixels: Int) {
        printWidth = Double(pixels) / resolution.pixelsPerUnit
        if keepAspect { printHeight = SizeMath.height(forWidth: printWidth, original: originalSize) }
    }

    public mutating func setPixelHeight(_ pixels: Int) {
        printHeight = Double(pixels) / resolution.pixelsPerUnit
        if keepAspect { printWidth = SizeMath.width(forHeight: printHeight, original: originalSize) }
    }

    public mutating func setPrintWidth(_ value: Double) {
        printWidth = value
        if keepAspect { printHeight = SizeMath.height(forWidth: value, original: originalSize) }
    }

    public mutating func setPrintHeight(_ value: Double) {
        printHeight = value
        if keepAspect { printWidth = SizeMath.width(forHeight: value, original: originalSize) }
    }

    /// Print size stays put, so the pixel size follows.
    public mutating func setResolution(_ pixelsPerUnit: Double) {
        resolution.pixelsPerUnit = pixelsPerUnit
    }

    /// Switches the displayed unit. The pixel size and physical size are unchanged.
    public mutating func setUnit(_ newUnit: MeasurementUnit) {
        guard newUnit != resolution.unit else { return }
        let factor: Double = newUnit == .centimeters ? MeasurementUnit.centimetersPerInch : 1 / MeasurementUnit.centimetersPerInch
        printWidth *= factor
        printHeight *= factor
        resolution = resolution.converted(to: newUnit)
    }

    /// Scales each side independently, the way "By percentage" does.
    public mutating func setPercent(_ percent: Double) {
        let size = SizeMath.size(percent: percent, of: originalSize)
        printWidth = Double(size.width) / resolution.pixelsPerUnit
        printHeight = Double(size.height) / resolution.pixelsPerUnit
    }
}
