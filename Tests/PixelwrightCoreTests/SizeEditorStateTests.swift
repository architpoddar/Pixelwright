import Testing
@testable import PixelwrightCore

@Suite("Size editor state")
struct SizeEditorStateTests {
    private func state(keepAspect: Bool = true, dpi: Double = 96) -> SizeEditorState {
        SizeEditorState(originalWidth: 960, originalHeight: 480,
                        resolution: ImageResolution(pixelsPerInch: dpi), keepAspect: keepAspect)
    }

    @Test("Starts at the original size: 960 px at 96 DPI is 10 inches")
    func initial() {
        let s = state()
        #expect(s.pixelWidth == 960 && s.pixelHeight == 480)
        #expect(abs(s.printWidth - 10) < 1e-12 && abs(s.printHeight - 5) < 1e-12)
        #expect(abs(s.percent - 100) < 1e-9)
        #expect(s.isValid)
    }

    @Test("Pixel width with the aspect lock updates height and print size")
    func pixelWidthLocked() {
        var s = state()
        s.setPixelWidth(480)
        #expect(s.pixelWidth == 480 && s.pixelHeight == 240)
        #expect(abs(s.printWidth - 5) < 1e-12)
        #expect(abs(s.percent - 50) < 1e-9)
    }

    @Test("Without the lock the other side is left alone")
    func pixelWidthUnlocked() {
        var s = state(keepAspect: false)
        s.setPixelWidth(100)
        #expect(s.pixelWidth == 100 && s.pixelHeight == 480)
    }

    @Test("Print width in inches sets pixels = print x resolution")
    func printWidth() {
        var s = state()
        s.setPrintWidth(2)
        #expect(s.pixelWidth == 192 && s.pixelHeight == 96)
    }

    @Test("Changing resolution keeps the print size and changes the pixels")
    func resolutionChange() {
        var s = state()
        s.setResolution(192)
        #expect(abs(s.printWidth - 10) < 1e-12)
        #expect(s.pixelWidth == 1920 && s.pixelHeight == 960)
        s.setResolution(48)
        #expect(s.pixelWidth == 480 && s.pixelHeight == 240)
    }

    @Test("Switching units keeps the pixel size and the physical size")
    func unitSwitch() {
        var s = state()
        s.setUnit(.centimeters)
        #expect(s.unit == .centimeters)
        #expect(s.pixelWidth == 960 && s.pixelHeight == 480)
        #expect(abs(s.printWidth - 25.4) < 1e-9)
        #expect(abs(s.resolution.pixelsPerUnit - 96 / 2.54) < 1e-9)
        s.setUnit(.inches)
        #expect(abs(s.printWidth - 10) < 1e-9)
        #expect(abs(s.resolution.pixelsPerUnit - 96) < 1e-9)
    }

    @Test("Percentage scales each side independently and rounds half away from zero")
    func percent() {
        var s = SizeEditorState(originalWidth: 5, originalHeight: 7,
                                resolution: .default, keepAspect: true)
        s.setPercent(50)
        #expect(s.pixelWidth == 3 && s.pixelHeight == 4) // 2.5 -> 3, 3.5 -> 4
    }

    @Test("Validity follows the pixel and resolution limits")
    func validity() {
        var s = state()
        s.setPixelWidth(300_000)
        #expect(!s.isValid)
        s.setPixelWidth(100)
        #expect(s.isValid)
        s.setResolution(0.005)
        #expect(!s.isValid)
        s.setResolution(300)
        #expect(s.isValid)
    }

    @Test("Resolution conversion round-trips")
    func resolutionRoundTrip() {
        let r = ImageResolution(pixelsPerInch: 300)
        let cm = r.converted(to: .centimeters)
        #expect(abs(cm.pixelsPerUnit - 300 / 2.54) < 1e-9)
        #expect(abs(cm.converted(to: .inches).pixelsPerUnit - 300) < 1e-9)
        #expect(abs(cm.pixelsPerInch - 300) < 1e-9)
    }
}
