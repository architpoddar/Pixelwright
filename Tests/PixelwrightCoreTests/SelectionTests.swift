import Testing
@testable import PixelwrightCore

/// 6x3 image: a red block on the left, blue on the right, a green divider column, and one more
/// red block cut off from the first by the divider.
///
///   R R G B R R
///   R R G B R R
///   R R G B R R
private func stripes() -> RasterImage {
    var img = RasterImage(width: 6, height: 3, fill: .black)
    let red = RGBA8(r: 255, g: 0, b: 0), green = RGBA8(r: 0, g: 255, b: 0), blue = RGBA8(r: 0, g: 0, b: 255)
    for y in 0..<3 {
        for x in 0..<6 { img[x, y] = [red, red, green, blue, red, red][x] }
    }
    return img
}

@Suite("Magic Wand")
struct MagicWandTests {
    @Test("Flood fill selects only the connected region")
    func contiguous() {
        let m = MagicWand.select(in: stripes(), x: 0, y: 0, tolerance: 0, mode: .contiguous)
        #expect(m.selectedCount == 6)
        #expect(m[0, 0] && m[1, 2])
        #expect(!m[4, 0] && !m[5, 2]) // same color, but not connected
    }

    @Test("Global mode selects every matching pixel, connected or not")
    func global() {
        let m = MagicWand.select(in: stripes(), x: 0, y: 0, tolerance: 0, mode: .global)
        #expect(m.selectedCount == 12)
        #expect(m[4, 0] && m[5, 2])
    }

    @Test("Connectivity is 4-way: a diagonal neighbor is not reached")
    func fourWay() {
        var img = RasterImage(width: 2, height: 2, fill: .white)
        img[1, 1] = .black
        img[0, 0] = .black
        let m = MagicWand.select(in: img, x: 0, y: 0, tolerance: 0, mode: .contiguous)
        #expect(m.selectedCount == 1) // (1, 1) touches only diagonally
    }

    @Test("Tolerance 0 needs an exact match; a higher tolerance admits near colors")
    func tolerance() {
        var img = RasterImage(width: 3, height: 1, fill: RGBA8(r: 100, g: 100, b: 100))
        img[1, 0] = RGBA8(r: 110, g: 100, b: 100)  // distance 10
        img[2, 0] = RGBA8(r: 200, g: 100, b: 100)  // distance 100
        #expect(MagicWand.select(in: img, x: 0, y: 0, tolerance: 0, mode: .global).selectedCount == 1)
        // 5% of 510 = 25.5, admits the near color only
        #expect(MagicWand.select(in: img, x: 0, y: 0, tolerance: 5, mode: .global).selectedCount == 2)
        // 25% of 510 = 127.5, admits all
        #expect(MagicWand.select(in: img, x: 0, y: 0, tolerance: 25, mode: .global).selectedCount == 3)
    }

    @Test("Tolerance 100 selects everything")
    func fullTolerance() {
        let m = MagicWand.select(in: stripes(), x: 2, y: 1, tolerance: 100, mode: .contiguous)
        #expect(m.selectedCount == 18)
    }

    @Test("Fully transparent pixels all count as the same color, whatever their RGB")
    func transparentPixelsMatch() {
        var img = RasterImage(width: 3, height: 1, fill: .clear)
        img[0, 0] = RGBA8(r: 255, g: 0, b: 0, a: 0)
        img[1, 0] = RGBA8(r: 0, g: 0, b: 255, a: 0)
        img[2, 0] = RGBA8(r: 0, g: 0, b: 0, a: 255)
        let m = MagicWand.select(in: img, x: 0, y: 0, tolerance: 0, mode: .global)
        #expect(m.selectedCount == 2 && !m[2, 0])
    }

    @Test("Clicking outside the image selects nothing")
    func outside() {
        #expect(MagicWand.select(in: stripes(), x: 99, y: 0, tolerance: 50, mode: .global).isEmpty)
        #expect(MagicWand.select(in: stripes(), x: -1, y: 0, tolerance: 50, mode: .global).isEmpty)
    }
}

@Suite("Selection mask")
struct SelectionMaskTests {
    @Test("Invert, union and subtract")
    func setOperations() {
        var a = SelectionMask(width: 2, height: 2)
        a[0, 0] = true
        var b = SelectionMask(width: 2, height: 2)
        b[0, 0] = true
        b[1, 1] = true
        #expect(a.inverted().selectedCount == 3)
        #expect(a.union(b).selectedCount == 2)
        #expect(b.subtracting(a).selectedCount == 1 && b.subtracting(a)[1, 1])
    }

    @Test("Clearing selected pixels makes them fully transparent and leaves the rest alone")
    func clearing() {
        let img = RasterImage(width: 2, height: 1, fill: RGBA8(r: 9, g: 8, b: 7))
        var mask = SelectionMask(width: 2, height: 1)
        mask[0, 0] = true
        let out = img.clearingPixels(in: mask)
        #expect(out[0, 0] == .clear)
        #expect(out[1, 0] == RGBA8(r: 9, g: 8, b: 7))
    }

    @Test("Growing and shrinking by a pixel")
    func growShrink() {
        var m = SelectionMask(width: 5, height: 5)
        m[2, 2] = true
        #expect(m.grown(by: 1).selectedCount == 5)   // plus shape
        #expect(m.grown(by: 1).grown(by: -1) == m)
        #expect(m.grown(by: -1).isEmpty)
        #expect(m.grown(by: 0) == m)
    }
}
