import AppKit
import Foundation
import PixelwrightCore
import Testing
@testable import Pixelwright

@MainActor
private func waitUntilIdle(_ model: AppModel, timeout: Double = 10) async {
    let deadline = Date().addingTimeInterval(timeout)
    while model.isBusy && Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    try? await Task.sleep(for: .milliseconds(20))
}

private func makeImageFile(named name: String = "photo.png") throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pixelwright-model-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    var img = RasterImage(width: 30, height: 20, fill: RGBA8(r: 10, g: 20, b: 30))
    img[0, 0] = RGBA8(r: 200, g: 0, b: 0)
    try img.write(to: url)
    return url
}

@Suite("Unsaved changes and the original file")
@MainActor
struct ModelStateTests {
    @Test("A freshly opened image isn't edited, and remembers where it came from")
    func opened() async throws {
        let url = try makeImageFile()
        let model = AppModel()
        model.open(url)
        await waitUntilIdle(model)
        #expect(model.hasImage && !model.isEdited)
        #expect(model.sourceURL == url)
        #expect(model.fileName == "photo.png")
    }

    @Test("Editing marks it edited; undoing back to the opened state clears that; redo marks it again")
    func editedTracking() async throws {
        let model = AppModel()
        model.open(try makeImageFile())
        await waitUntilIdle(model)

        model.rotate(.clockwise90)
        await waitUntilIdle(model)
        #expect(model.isEdited)
        #expect(model.image?.width == 20 && model.image?.height == 30)

        model.undo()
        #expect(!model.isEdited)
        #expect(model.image?.width == 30)

        model.redo()
        #expect(model.isEdited)
    }

    @Test("Undo then a different edit is a new, unsaved state, not the saved one")
    func differentEditAfterUndo() async throws {
        let model = AppModel()
        model.open(try makeImageFile())
        await waitUntilIdle(model)

        model.rotate(.clockwise90)
        await waitUntilIdle(model)
        model.undo()
        model.flipHorizontally()  // same number of steps from the start, but a different picture
        await waitUntilIdle(model)
        #expect(model.isEdited)
    }

    @Test("The original file on disk is never touched by editing")
    func originalUntouched() async throws {
        let url = try makeImageFile()
        let before = try Data(contentsOf: url)
        let model = AppModel()
        model.open(url)
        await waitUntilIdle(model)
        model.rotate(.half)
        await waitUntilIdle(model)
        model.applyEffect(.invertColors)
        await waitUntilIdle(model)
        model.resize(width: 5, height: 5, method: .bicubic, gamma: true, resolution: .default)
        await waitUntilIdle(model)
        #expect(model.isEdited)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("Closing the image forgets it and its edits")
    func closing() async throws {
        let model = AppModel()
        model.open(try makeImageFile())
        await waitUntilIdle(model)
        model.rotate(.half)
        await waitUntilIdle(model)
        model.closeImage()
        #expect(!model.hasImage && !model.isEdited && model.sourceURL == nil && !model.canUndo)
    }

    @Test("Asking to discard an unedited image needs no confirmation")
    func noPromptWhenClean() async throws {
        let model = AppModel()
        #expect(model.confirmDiscardIfNeeded(action: "quit")) // no image at all
        model.open(try makeImageFile())
        await waitUntilIdle(model)
        #expect(model.confirmDiscardIfNeeded(action: "quit")) // opened but unchanged
    }
}

@Suite("Is it the same file?")
struct SameFileTests {
    @Test("A file is the same as itself, and different from another file")
    func basic() throws {
        let a = try makeImageFile(named: "a.png")
        let b = a.deletingLastPathComponent().appendingPathComponent("b.png")
        try Data("x".utf8).write(to: b)
        #expect(AppModel.isSameFile(a, a))
        #expect(!AppModel.isSameFile(a, b))
    }

    @Test("A path with extra components that leads to the same file counts as the same")
    func roundabout() throws {
        let a = try makeImageFile(named: "a.png")
        let roundabout = a.deletingLastPathComponent().appendingPathComponent("../\(a.deletingLastPathComponent().lastPathComponent)/a.png")
        #expect(AppModel.isSameFile(a, roundabout))
    }

    @Test("A name that doesn't exist yet is never the original")
    func notYetThere() throws {
        let a = try makeImageFile(named: "a.png")
        let new = a.deletingLastPathComponent().appendingPathComponent("a edited.png")
        #expect(!AppModel.isSameFile(a, new))
    }
}

@Suite("Opening files from outside the app")
@MainActor
struct OpenFromFinderTests {
    @Test("A file opened while the app is running reaches the model, and a second one replaces the first")
    func delegateOpens() async throws {
        let first = try makeImageFile(named: "first.png")
        let second = try makeImageFile(named: "second.png")
        let model = AppModel.shared
        defer { model.closeImage() }

        AppDelegate().application(NSApplication.shared, open: [first])
        await waitUntilIdle(model)
        #expect(model.sourceURL == first)

        AppDelegate().application(NSApplication.shared, open: [second])
        await waitUntilIdle(model)
        #expect(model.sourceURL == second)
        #expect(model.fileName == "second.png")
    }
}
