import Testing
@testable import PixelwrightCore

@Suite("Batch resize sizing")
struct BatchResizeTests {
    @Test("Longest side scales landscape and portrait images the same way")
    func longestSide() {
        let mode = BatchResizeMode.longestSide(pixels: 1000)
        #expect(mode.targetSize(width: 4000, height: 3000, allowEnlarging: true) == (1000, 750))
        #expect(mode.targetSize(width: 3000, height: 4000, allowEnlarging: true) == (750, 1000))
        #expect(mode.targetSize(width: 3000, height: 3000, allowEnlarging: true) == (1000, 1000))
    }

    @Test("Smaller images stay as they are unless enlarging is allowed")
    func noEnlarge() {
        let mode = BatchResizeMode.longestSide(pixels: 1000)
        #expect(mode.targetSize(width: 400, height: 200, allowEnlarging: false) == (400, 200))
        #expect(mode.targetSize(width: 400, height: 200, allowEnlarging: true) == (1000, 500))
    }

    @Test("Fit within a box uses whichever side is the tighter limit")
    func fitWithin() {
        let box = BatchResizeMode.fitWithin(maxWidth: 800, maxHeight: 600)
        #expect(box.targetSize(width: 1600, height: 1600, allowEnlarging: false) == (600, 600))
        #expect(box.targetSize(width: 1600, height: 400, allowEnlarging: false) == (800, 200))
        let widthOnly = BatchResizeMode.fitWithin(maxWidth: 500, maxHeight: nil)
        #expect(widthOnly.targetSize(width: 1000, height: 800, allowEnlarging: false) == (500, 400))
        let heightOnly = BatchResizeMode.fitWithin(maxWidth: nil, maxHeight: 100)
        #expect(heightOnly.targetSize(width: 1000, height: 500, allowEnlarging: false) == (200, 100))
    }

    @Test("Percentage scales both sides and rounds half away from zero")
    func percentage() {
        #expect(BatchResizeMode.percentage(50).targetSize(width: 5, height: 7, allowEnlarging: true) == (3, 4))
        #expect(BatchResizeMode.percentage(200).targetSize(width: 5, height: 7, allowEnlarging: false) == (5, 7))
        #expect(BatchResizeMode.percentage(200).targetSize(width: 5, height: 7, allowEnlarging: true) == (10, 14))
    }

    @Test("Results stay within 1 and the pixel limit")
    func limits() {
        #expect(BatchResizeMode.percentage(0.01).targetSize(width: 10, height: 10, allowEnlarging: true) == (1, 1))
        let huge = BatchResizeMode.longestSide(pixels: 10_000_000).targetSize(width: 100, height: 50, allowEnlarging: true)
        #expect(huge.width == 262_144)
    }

    @Test("Validity")
    func validity() {
        #expect(BatchResizeMode.longestSide(pixels: 1).isValid)
        #expect(!BatchResizeMode.longestSide(pixels: 0).isValid)
        #expect(!BatchResizeMode.fitWithin(maxWidth: nil, maxHeight: nil).isValid)
        #expect(!BatchResizeMode.fitWithin(maxWidth: 0, maxHeight: 10).isValid)
        #expect(BatchResizeMode.fitWithin(maxWidth: 10, maxHeight: nil).isValid)
        #expect(!BatchResizeMode.percentage(0).isValid)
    }
}

@Suite("Batch file names")
struct BatchNamingTests {
    @Test("Adds the suffix and swaps the extension")
    func names() {
        #expect(BatchNaming.outputName(for: "photo.jpg", suffix: "-small", fileExtension: "png") == "photo-small.png")
        #expect(BatchNaming.outputName(for: "my.holiday.heic", suffix: "", fileExtension: "jpg") == "my.holiday.jpg")
        #expect(BatchNaming.outputName(for: "noext", suffix: "_x", fileExtension: "png") == "noext_x.png")
    }

    @Test("Never overwrites: takes the next free number")
    func unique() {
        let taken: Set<String> = ["a.png", "a 2.png", "a 3.png"]
        #expect(BatchNaming.uniqueName("a.png", exists: { taken.contains($0) }) == "a 4.png")
        #expect(BatchNaming.uniqueName("b.png", exists: { taken.contains($0) }) == "b.png")
    }
}

@Suite("Suggested names for saved copies")
struct SaveNamingTests {
    @Test("Adds 'edited' and never offers the original's name")
    func edited() {
        let name = SaveNaming.suggestedCopyName(original: "holiday.jpg", fileExtension: "jpg", exists: { _ in false })
        #expect(name == "holiday edited.jpg")
        #expect(name != "holiday.jpg")
    }

    @Test("Keeps a dotted name intact and swaps the extension")
    func dotted() {
        #expect(SaveNaming.suggestedCopyName(original: "my.trip.heic", fileExtension: "png", exists: { _ in false }) == "my.trip edited.png")
    }

    @Test("Picks a free name when the suggestion already exists")
    func unique() {
        let taken: Set<String> = ["a edited.png", "a edited 2.png"]
        #expect(SaveNaming.suggestedCopyName(original: "a.png", fileExtension: "png", exists: { taken.contains($0) }) == "a edited 3.png")
    }

    @Test("An image with no file behind it is called Untitled")
    func untitled() {
        #expect(SaveNaming.suggestedCopyName(original: nil, fileExtension: "png", exists: { _ in false }) == "Untitled.png")
        #expect(SaveNaming.suggestedCopyName(original: nil, fileExtension: "png", exists: { $0 == "Untitled.png" }) == "Untitled 2.png")
    }
}
