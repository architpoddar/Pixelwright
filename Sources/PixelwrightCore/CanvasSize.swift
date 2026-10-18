/// Where the existing image sits when the canvas changes size (3x3 grid).
public enum AnchorEdge: Int, CaseIterable, Sendable {
    case topLeft = 0, top, topRight, left, middle, right, bottomLeft, bottom, bottomRight

    /// For tooltips and accessibility: where the picture stays when the canvas changes.
    public var displayName: String {
        switch self {
        case .topLeft: "Top left"
        case .top: "Top"
        case .topRight: "Top right"
        case .left: "Left"
        case .middle: "Center"
        case .right: "Right"
        case .bottomLeft: "Bottom left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom right"
        }
    }

    /// Offset of the old image inside the new canvas. Spec section 2.2: the middle offsets
    /// use integer division that truncates toward zero, which Swift's `/` does.
    func offset(oldWidth: Int, oldHeight: Int, newWidth: Int, newHeight: Int) -> (x: Int, y: Int) {
        let dx = newWidth - oldWidth
        let dy = newHeight - oldHeight
        let hx = dx / 2
        let hy = dy / 2
        switch self {
        case .topLeft: return (0, 0)
        case .top: return (hx, 0)
        case .topRight: return (dx, 0)
        case .left: return (0, hy)
        case .middle: return (hx, hy)
        case .right: return (dx, hy)
        case .bottomLeft: return (0, dy)
        case .bottom: return (hx, dy)
        case .bottomRight: return (dx, dy)
        }
    }
}

/// What fills the new space when the canvas grows.
public enum CanvasFill: Sendable, Equatable {
    case transparent
    case primary(RGBA8)
    case secondary(RGBA8)
    case white
    case black

    public var color: RGBA8 {
        switch self {
        case .transparent: .clear
        case .primary(let c), .secondary(let c): c
        case .white: .white
        case .black: .black
        }
    }
}

public enum CanvasSize {
    /// Returns a new image of `newWidth` x `newHeight`. The whole canvas is first filled, then
    /// the old pixels are copied (not blended) at the anchor offset. Anything outside the new
    /// bounds is cropped.
    public static func resize(
        _ image: RasterImage,
        newWidth: Int,
        newHeight: Int,
        anchor: AnchorEdge,
        fill: CanvasFill
    ) -> RasterImage {
        var result = RasterImage(width: newWidth, height: newHeight, fill: fill.color)
        let (ox, oy) = anchor.offset(
            oldWidth: image.width, oldHeight: image.height,
            newWidth: newWidth, newHeight: newHeight
        )

        // Visible span of the old image in destination coordinates.
        let dstX0 = max(0, ox)
        let dstX1 = min(newWidth, ox + image.width)
        let dstY0 = max(0, oy)
        let dstY1 = min(newHeight, oy + image.height)
        guard dstX0 < dstX1, dstY0 < dstY1 else { return result }

        let rowBytes = (dstX1 - dstX0) * 4
        image.pixels.withUnsafeBufferPointer { src in
            result.pixels.withUnsafeMutableBufferPointer { dst in
                for y in dstY0..<dstY1 {
                    let srcStart = ((y - oy) * image.width + (dstX0 - ox)) * 4
                    let dstStart = (y * newWidth + dstX0) * 4
                    for i in 0..<rowBytes {
                        dst[dstStart + i] = src[srcStart + i]
                    }
                }
            }
        }
        return result
    }
}
