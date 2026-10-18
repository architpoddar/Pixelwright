import Testing
@testable import PixelwrightCore

/// 3 wide x 2 tall; each pixel's red channel is its index:
///   0 1 2
///   3 4 5
private func numbered() -> RasterImage {
    var img = RasterImage(width: 3, height: 2, fill: .black)
    for i in 0..<6 { img[i % 3, i / 3] = RGBA8(r: UInt8(i), g: 0, b: 0) }
    return img
}

private func reds(_ img: RasterImage) -> [Int] {
    (0..<(img.width * img.height)).map { Int(img[$0 % img.width, $0 / img.width].r) }
}

@Suite("Rotate and flip")
struct RotateFlipTests {
    @Test("Rotating 90 degrees clockwise")
    func clockwise() {
        let r = ImageTransform.rotated(numbered(), .clockwise90)
        #expect(r.width == 2 && r.height == 3)
        #expect(reds(r) == [3, 0, 4, 1, 5, 2])
    }

    @Test("Rotating 90 degrees counterclockwise")
    func counterclockwise() {
        let r = ImageTransform.rotated(numbered(), .counterclockwise90)
        #expect(r.width == 2 && r.height == 3)
        #expect(reds(r) == [2, 5, 1, 4, 0, 3])
    }

    @Test("Rotating 180 degrees")
    func half() {
        let r = ImageTransform.rotated(numbered(), .half)
        #expect(r.width == 3 && r.height == 2)
        #expect(reds(r) == [5, 4, 3, 2, 1, 0])
    }

    @Test("Four quarter turns, or clockwise then counterclockwise, give the original back")
    func roundTrips() {
        let img = numbered()
        var r = img
        for _ in 0..<4 { r = ImageTransform.rotated(r, .clockwise90) }
        #expect(r == img)
        #expect(ImageTransform.rotated(ImageTransform.rotated(img, .clockwise90), .counterclockwise90) == img)
        #expect(ImageTransform.rotated(ImageTransform.rotated(img, .half), .half) == img)
    }

    @Test("Flipping")
    func flips() {
        #expect(reds(ImageTransform.flippedHorizontally(numbered())) == [2, 1, 0, 5, 4, 3])
        #expect(reds(ImageTransform.flippedVertically(numbered())) == [3, 4, 5, 0, 1, 2])
        let img = numbered()
        #expect(ImageTransform.flippedHorizontally(ImageTransform.flippedHorizontally(img)) == img)
        #expect(ImageTransform.flippedVertically(ImageTransform.flippedVertically(img)) == img)
    }

    @Test("Rotation keeps alpha and color together")
    func keepsChannels() {
        var img = RasterImage(width: 2, height: 1, fill: .clear)
        img[0, 0] = RGBA8(r: 1, g: 2, b: 3, a: 4)
        let r = ImageTransform.rotated(img, .clockwise90)
        #expect(r[0, 0] == RGBA8(r: 1, g: 2, b: 3, a: 4))
        #expect(r[0, 1] == .clear)
    }
}

@Suite("Crop")
struct CropTests {
    @Test("Cropping returns exactly the requested pixels")
    func crop() {
        let c = ImageTransform.cropped(numbered(), to: PixelRect(x: 1, y: 0, width: 2, height: 2))!
        #expect(c.width == 2 && c.height == 2)
        #expect(reds(c) == [1, 2, 4, 5])
    }

    @Test("A rectangle that sticks out is clamped; one that misses gives nil")
    func clamping() {
        let c = ImageTransform.cropped(numbered(), to: PixelRect(x: 2, y: 1, width: 10, height: 10))!
        #expect(c.width == 1 && c.height == 1 && reds(c) == [5])
        #expect(ImageTransform.cropped(numbered(), to: PixelRect(x: 5, y: 5, width: 2, height: 2)) == nil)
        #expect(ImageTransform.cropped(numbered(), to: PixelRect(x: 0, y: 0, width: 0, height: 3)) == nil)
    }

    @Test("Auto-crop trims transparent borders")
    func autoCrop() {
        var img = RasterImage(width: 6, height: 5, fill: .clear)
        img[2, 1] = RGBA8(r: 9, g: 9, b: 9)
        img[3, 3] = RGBA8(r: 8, g: 8, b: 8, a: 1) // almost invisible still counts
        #expect(ImageTransform.opaqueBounds(img) == PixelRect(x: 2, y: 1, width: 2, height: 3))
        let c = ImageTransform.autoCropped(img)!
        #expect(c.width == 2 && c.height == 3)
        #expect(c[0, 0].r == 9 && c[1, 2].r == 8)
    }

    @Test("A fully transparent image can't be auto-cropped; an opaque one is unchanged")
    func autoCropEdges() {
        #expect(ImageTransform.autoCropped(RasterImage(width: 3, height: 3, fill: .clear)) == nil)
        let solid = RasterImage(width: 3, height: 3, fill: .white)
        #expect(ImageTransform.autoCropped(solid) == solid)
    }

    @Test("Selection bounds and rectangularity")
    func selectionBounds() {
        var m = SelectionMask(width: 5, height: 5)
        #expect(m.bounds == nil && !m.isRectangular)
        m[1, 1] = true; m[2, 1] = true; m[1, 2] = true; m[2, 2] = true
        #expect(m.bounds == PixelRect(x: 1, y: 1, width: 2, height: 2) && m.isRectangular)
        m[3, 3] = true
        #expect(m.bounds == PixelRect(x: 1, y: 1, width: 3, height: 3) && !m.isRectangular)
    }

    @Test("Crop to a rectangular selection keeps every pixel")
    func cropToRect() {
        var m = SelectionMask(width: 3, height: 2)
        m[1, 0] = true; m[2, 0] = true; m[1, 1] = true; m[2, 1] = true
        let c = numbered().croppedToSelection(m)!
        #expect(reds(c) == [1, 2, 4, 5])
    }

    @Test("Crop to an irregular selection cuts out its shape")
    func cropToShape() {
        var m = SelectionMask(width: 3, height: 2)
        m[0, 0] = true; m[1, 0] = true; m[1, 1] = true  // an L missing (0,1)
        let c = numbered().croppedToSelection(m)!
        #expect(c.width == 2 && c.height == 2)
        #expect(c[0, 0].r == 0 && c[1, 0].r == 1 && c[1, 1].r == 4)
        #expect(c[0, 1] == .clear)
        #expect(SelectionMask(width: 3, height: 2).isEmpty)
        #expect(numbered().croppedToSelection(SelectionMask(width: 3, height: 2)) == nil)
    }
}
