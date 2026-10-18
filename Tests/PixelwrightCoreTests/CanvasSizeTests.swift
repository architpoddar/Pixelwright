import Testing
@testable import PixelwrightCore

/// Image where every pixel encodes its own position, so we can see where it ended up.
private func positionImage(width: Int, height: Int) -> RasterImage {
    var img = RasterImage(width: width, height: height, fill: .clear)
    for y in 0..<height {
        for x in 0..<width {
            img[x, y] = RGBA8(r: UInt8(x % 256), g: UInt8(y % 256), b: 1, a: 255)
        }
    }
    return img
}

/// Where old pixel (0, 0) lands in the new canvas, found by scanning for its marker.
private func locateOrigin(in img: RasterImage) -> (x: Int, y: Int)? {
    for y in 0..<img.height {
        for x in 0..<img.width where img[x, y] == RGBA8(r: 0, g: 0, b: 1, a: 255) {
            return (x, y)
        }
    }
    return nil
}

@Suite("Canvas Size")
struct CanvasSizeTests {
    @Test("Growing 100x50 to 105x53 places the image per anchor (spec 2.2)")
    func growOffsets() {
        let old = positionImage(width: 100, height: 50)
        // dx = 5, dy = 3, hx = 2, hy = 1
        let expected: [AnchorEdge: (Int, Int)] = [
            .topLeft: (0, 0), .top: (2, 0), .topRight: (5, 0),
            .left: (0, 1), .middle: (2, 1), .right: (5, 1),
            .bottomLeft: (0, 3), .bottom: (2, 3), .bottomRight: (5, 3),
        ]
        for anchor in AnchorEdge.allCases {
            let out = CanvasSize.resize(old, newWidth: 105, newHeight: 53, anchor: anchor, fill: .transparent)
            let found = locateOrigin(in: out)
            #expect(found?.x == expected[anchor]!.0 && found?.y == expected[anchor]!.1, "anchor \(anchor)")
        }
    }

    @Test("Shrinking with Middle truncates toward zero: 100 -> 95 crops 2 left, 3 right")
    func shrinkMiddleTruncation() {
        let old = positionImage(width: 100, height: 10)
        let out = CanvasSize.resize(old, newWidth: 95, newHeight: 10, anchor: .middle, fill: .transparent)
        #expect(out.width == 95)
        // New x = 0 shows old x = 2; new x = 94 shows old x = 96.
        #expect(out[0, 0].r == 2)
        #expect(out[94, 0].r == 96)
    }

    @Test("Shrinking crops: bottom-right anchor keeps the bottom-right corner")
    func shrinkBottomRight() {
        let old = positionImage(width: 10, height: 10)
        let out = CanvasSize.resize(old, newWidth: 4, newHeight: 3, anchor: .bottomRight, fill: .white)
        #expect(out[0, 0].r == 6 && out[0, 0].g == 7)
        #expect(out[3, 2].r == 9 && out[3, 2].g == 9)
    }

    @Test("New space is filled with the chosen color; old pixels are copied, not blended")
    func fillAndCopy() {
        var old = RasterImage(width: 2, height: 2, fill: RGBA8(r: 10, g: 20, b: 30, a: 255))
        old[0, 0] = .clear // transparent source pixel must overwrite the fill, not show through it
        let red = RGBA8(r: 255, g: 0, b: 0)
        let out = CanvasSize.resize(old, newWidth: 4, newHeight: 4, anchor: .middle, fill: .primary(red))
        #expect(out[0, 0] == red)
        #expect(out[1, 1] == .clear)
        #expect(out[2, 2] == RGBA8(r: 10, g: 20, b: 30, a: 255))
    }

    @Test("Fill choices map to the right colors")
    func fillColors() {
        let c = RGBA8(r: 1, g: 2, b: 3)
        #expect(CanvasFill.transparent.color == RGBA8(r: 0, g: 0, b: 0, a: 0))
        #expect(CanvasFill.white.color == RGBA8(r: 255, g: 255, b: 255, a: 255))
        #expect(CanvasFill.black.color == RGBA8(r: 0, g: 0, b: 0, a: 255))
        #expect(CanvasFill.primary(c).color == c)
        #expect(CanvasFill.secondary(c).color == c)
    }

    @Test("A canvas with no overlap with the image is all fill")
    func noOverlap() {
        let old = positionImage(width: 4, height: 4)
        let out = CanvasSize.resize(old, newWidth: 1, newHeight: 1, anchor: .middle, fill: .white)
        // dx = dy = -3, offset = -1: the single pixel is old (1, 1)
        #expect(out[0, 0].r == 1 && out[0, 0].g == 1)
    }
}
