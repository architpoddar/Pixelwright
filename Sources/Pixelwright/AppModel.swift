import AppKit
import PixelwrightCore
import SwiftUI
import UniformTypeIdentifiers

/// One open image with simple snapshot-based undo/redo.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var image: RasterImage?
    @Published private(set) var fileName: String = "Untitled"
    @Published private(set) var isBusy = false
    @Published private(set) var busyMessage = ""
    @Published var errorMessage: String?
    @Published var showingResize = false
    @Published var showingCanvasSize = false

    private var undoStack: [RasterImage] = []
    private var redoStack: [RasterImage] = []
    private let maxUndoSteps = 20

    var hasImage: Bool { image != nil }
    var canUndo: Bool { !undoStack.isEmpty && !isBusy }
    var canRedo: Bool { !redoStack.isEmpty && !isBusy }
    var canEdit: Bool { hasImage && !isBusy }

    // MARK: Files

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        run("Opening…") {
            let loaded = try RasterImage.load(from: url)
            await MainActor.run {
                self.image = loaded
                self.fileName = url.lastPathComponent
                self.undoStack.removeAll()
                self.redoStack.removeAll()
            }
        }
    }

    func saveWithPanel() {
        guard let image else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.nameFieldStringValue = (fileName as NSString).deletingPathExtension + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run("Saving…") { try image.write(to: url) }
    }

    // MARK: Edits

    func resize(width: Int, height: Int, method: ResamplingMethod, gamma: Bool) {
        edit("Resizing…") { image in
            Resampler.resize(image, width: width, height: height, method: method, gammaCorrect: gamma)
        }
    }

    func resizeCanvas(width: Int, height: Int, anchor: AnchorEdge, fill: CanvasFill) {
        edit("Resizing canvas…") { image in
            CanvasSize.resize(image, newWidth: width, newHeight: height, anchor: anchor, fill: fill)
        }
    }

    func removeBackground() {
        edit("Removing background…") { image in
            try BackgroundRemoval.removeBackground(from: image)
        }
    }

    func undo() {
        guard let current = image, let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        image = previous
    }

    func redo() {
        guard let current = image, let next = redoStack.popLast() else { return }
        undoStack.append(current)
        image = next
    }

    // MARK: Plumbing

    /// Runs `transform` off the main thread, then swaps in the result as one undo step.
    private func edit(_ message: String, _ transform: @escaping @Sendable (RasterImage) throws -> RasterImage) {
        guard let original = image, !isBusy else { return }
        run(message) {
            let result = try transform(original)
            await MainActor.run {
                self.undoStack.append(original)
                if self.undoStack.count > self.maxUndoSteps { self.undoStack.removeFirst() }
                self.redoStack.removeAll()
                self.image = result
            }
        }
    }

    private func run(_ message: String, _ work: @escaping @Sendable () async throws -> Void) {
        isBusy = true
        busyMessage = message
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try await work() }.value
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }
}
