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

@Suite("Selection shapes")
struct SelectionShapeTests {
    @Test("Rectangle selects exactly its area and is clamped to the image")
    func rectangle() {
        let m = SelectionMask.rectangle(width: 6, height: 4, rect: PixelRect(x: 1, y: 1, width: 3, height: 2))
        #expect(m.selectedCount == 6 && m[1, 1] && m[3, 2] && !m[4, 1] && !m[0, 1])
        let clamped = SelectionMask.rectangle(width: 4, height: 4, rect: PixelRect(x: 2, y: 2, width: 99, height: 99))
        #expect(clamped.selectedCount == 4 && clamped.bounds == PixelRect(x: 2, y: 2, width: 2, height: 2))
        #expect(SelectionMask.rectangle(width: 4, height: 4, rect: PixelRect(x: 9, y: 9, width: 2, height: 2)).isEmpty)
    }

    @Test("A polygon that traces a rectangle selects the same pixels as that rectangle")
    func polygonRectangle() {
        let poly = SelectionMask.polygon(width: 8, height: 8, points: [(2, 1), (6, 1), (6, 5), (2, 5)])
        let rect = SelectionMask.rectangle(width: 8, height: 8, rect: PixelRect(x: 2, y: 1, width: 4, height: 4))
        #expect(poly == rect)
    }

    @Test("A triangle selects roughly half of its bounding box")
    func triangle() {
        let t = SelectionMask.polygon(width: 20, height: 20, points: [(0, 0), (20, 0), (0, 20)])
        #expect((180...220).contains(t.selectedCount), "got \(t.selectedCount)")
        #expect(t[1, 1] && !t[18, 18])
    }

    @Test("Winding either way gives the same result; fewer than 3 points select nothing")
    func orderAndDegenerate() {
        let a = SelectionMask.polygon(width: 10, height: 10, points: [(1, 1), (8, 2), (5, 9)])
        let b = SelectionMask.polygon(width: 10, height: 10, points: [(5, 9), (8, 2), (1, 1)])
        #expect(a == b && !a.isEmpty)
        #expect(SelectionMask.polygon(width: 5, height: 5, points: [(0, 0), (4, 4)]).isEmpty)
    }

    @Test("Points outside the image are clipped")
    func clipped() {
        let m = SelectionMask.polygon(width: 4, height: 4, points: [(-10, -10), (50, -10), (50, 50), (-10, 50)])
        #expect(m.selectedCount == 16)
    }
}

@Suite("Feathered edges")
struct FeatherTests {
    /// 21 x 5 white image whose left 10 columns are selected: a vertical edge between x = 9 and 10.
    private func edgeCase() -> (RasterImage, SelectionMask) {
        let img = RasterImage(width: 21, height: 5, fill: .white)
        var m = SelectionMask(width: 21, height: 5)
        for y in 0..<5 { for x in 0..<10 { m[x, y] = true } }
        return (img, m)
    }

    @Test("Feather 0 is the same as the hard delete")
    func zeroIsHard() {
        let (img, m) = edgeCase()
        #expect(img.clearingPixels(in: m, feather: 0) == img.clearingPixels(in: m))
        #expect(img.clearingPixels(in: m)[9, 2].a == 0 && img.clearingPixels(in: m)[10, 2].a == 255)
    }

    @Test("Coverage is 1 deep inside, 0 far outside, and about one half at the boundary")
    func coverageProfile() {
        let (_, m) = edgeCase()
        let c = m.softCoverage(radius: 2)
        func at(_ x: Int) -> Float { c[2 * 21 + x] }
        #expect(at(0) > 0.999 || at(0) > 0.9) // against the border: replicated, stays selected
        #expect(at(2) > 0.99)
        #expect(at(18) < 0.001)
        // Symmetric around the boundary between columns 9 and 10.
        #expect(abs(at(9) + at(10) - 1) < 0.01)
        #expect(at(9) > at(10))
        // Falls monotonically across the edge.
        for x in 5..<14 { #expect(at(x) >= at(x + 1) - 1e-6) }
    }

    @Test("A feathered delete leaves partly transparent pixels along the edge")
    func softEdge() {
        let (img, m) = edgeCase()
        let out = img.clearingPixels(in: m, feather: 3)
        #expect(out[0, 2].a == 0)          // deep inside the selection: fully cleared
        #expect(out[20, 2].a == 255)       // far outside: untouched
        let edge = [out[8, 2].a, out[9, 2].a, out[10, 2].a, out[11, 2].a]
        #expect(edge.contains { $0 > 0 && $0 < 255 })
        #expect(edge == edge.sorted()) // alpha rises moving away from the selection
    }

    @Test("A selection touching the image border doesn't fade near it")
    func borderReplication() {
        let img = RasterImage(width: 9, height: 9, fill: .white)
        let m = SelectionMask(width: 9, height: 9, selected: true)
        let out = img.clearingPixels(in: m, feather: 4)
        #expect(out.pixels.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 0 })
    }

    @Test("Feathering never raises alpha, and keeps color of surviving pixels")
    func keepsColor() {
        var img = RasterImage(width: 21, height: 5, fill: RGBA8(r: 10, g: 20, b: 30, a: 200))
        img[19, 2] = RGBA8(r: 1, g: 2, b: 3, a: 100)
        let (_, m) = edgeCase()
        let out = img.clearingPixels(in: m, feather: 2)
        #expect(out[19, 2] == RGBA8(r: 1, g: 2, b: 3, a: 100))
        for p in 0..<(21 * 5) { #expect(out.pixels[p * 4 + 3] <= img.pixels[p * 4 + 3]) }
        #expect(out[10, 2].r == 10 && out[10, 2].g == 20)
    }
}
