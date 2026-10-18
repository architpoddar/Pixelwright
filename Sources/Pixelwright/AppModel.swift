import AppKit
import PixelwrightCore
import SwiftUI
import UniformTypeIdentifiers

enum Tool: Equatable {
    case none
    case magicWand
}

/// One open image with simple snapshot-based undo/redo.
@MainActor
final class AppModel: ObservableObject {
    /// What undo restores: the pixels and the resolution they were saved with.
    private struct Snapshot {
        let image: RasterImage
        let resolution: ImageResolution
    }

    @Published private(set) var image: RasterImage?
    @Published private(set) var resolution: ImageResolution = .default
    @Published private(set) var fileName: String = "Untitled"
    @Published private(set) var isBusy = false
    @Published private(set) var busyMessage = ""
    @Published var errorMessage: String?
    @Published var showingResize = false
    @Published var showingCanvasSize = false

    // Selection and the Magic Wand
    @Published var tool: Tool = .none
    @Published var wandTolerance: Double = 25
    @Published var wandMode: MagicWandMode = .contiguous
    @Published private(set) var selection: SelectionMask?
    @Published private(set) var selectionOverlay: CGImage?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let maxUndoSteps = 20

    var hasImage: Bool { image != nil }
    var canUndo: Bool { !undoStack.isEmpty && !isBusy }
    var canRedo: Bool { !redoStack.isEmpty && !isBusy }
    var canEdit: Bool { hasImage && !isBusy }
    var hasSelection: Bool { selection != nil }

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
                self.image = loaded.image
                self.resolution = loaded.resolution
                self.fileName = url.lastPathComponent
                self.undoStack.removeAll()
                self.redoStack.removeAll()
                self.setSelection(nil)
            }
        }
    }

    func saveWithPanel() {
        guard let image else { return }
        let resolution = self.resolution
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.nameFieldStringValue = (fileName as NSString).deletingPathExtension + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run("Saving…") { try image.write(to: url, resolution: resolution) }
    }

    // MARK: Edits

    func resize(width: Int, height: Int, method: ResamplingMethod, gamma: Bool, resolution newResolution: ImageResolution) {
        edit("Resizing…", resolution: newResolution) { image in
            Resampler.resize(image, width: width, height: height, method: method, gammaCorrect: gamma)
        }
    }

    func resizeCanvas(width: Int, height: Int, anchor: AnchorEdge, fill: CanvasFill, resolution newResolution: ImageResolution) {
        edit("Resizing canvas…", resolution: newResolution) { image in
            CanvasSize.resize(image, newWidth: width, newHeight: height, anchor: anchor, fill: fill)
        }
    }

    func removeBackground() {
        edit("Removing background…") { image in
            try BackgroundRemoval.removeBackground(from: image)
        }
    }

    /// Makes the selected pixels transparent.
    func deleteSelection() {
        guard let mask = selection else { return }
        edit("Deleting selection…") { image in image.clearingPixels(in: mask) }
    }

    func undo() {
        guard let current = image, let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(image: current, resolution: resolution))
        apply(previous)
    }

    func redo() {
        guard let current = image, let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(image: current, resolution: resolution))
        apply(next)
    }

    private func apply(_ snapshot: Snapshot) {
        image = snapshot.image
        resolution = snapshot.resolution
        setSelection(nil)
    }

    // MARK: Selection

    func selectAll() {
        guard let image else { return }
        setSelection(SelectionMask(width: image.width, height: image.height, selected: true))
    }

    func deselect() { setSelection(nil) }

    func invertSelection() {
        guard let image else { return }
        let base = selection ?? SelectionMask(width: image.width, height: image.height)
        setSelection(base.inverted())
    }

    func growSelection(by pixels: Int) {
        guard let mask = selection else { return }
        Task {
            let result = await Task.detached { mask.grown(by: pixels) }.value
            setSelection(result.isEmpty ? nil : result)
        }
    }

    enum SelectionCombine { case replace, add, subtract }

    /// A click with the Magic Wand at a pixel position.
    func wandClick(x: Int, y: Int, combine: SelectionCombine) {
        guard let image, !isBusy else { return }
        let tolerance = wandTolerance, mode = wandMode, current = selection
        Task {
            let picked = await Task.detached {
                MagicWand.select(in: image, x: x, y: y, tolerance: tolerance, mode: mode)
            }.value
            switch combine {
            case .replace: setSelection(picked.isEmpty ? nil : picked)
            case .add: setSelection(current.map { $0.union(picked) } ?? picked)
            case .subtract:
                if let current { let r = current.subtracting(picked); setSelection(r.isEmpty ? nil : r) }
            }
        }
    }

    private func setSelection(_ mask: SelectionMask?) {
        selection = mask
        selectionOverlay = mask.flatMap(Self.makeOverlay)
    }

    /// A translucent blue tint over the selected pixels.
    private static func makeOverlay(for mask: SelectionMask) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        for p in 0..<(mask.width * mask.height) where mask.flags[p] {
            bytes[p * 4] = 30; bytes[p * 4 + 1] = 120; bytes[p * 4 + 2] = 255; bytes[p * 4 + 3] = 110
        }
        return RasterImage(width: mask.width, height: mask.height, pixels: bytes).makeCGImage()
    }

    // MARK: Plumbing

    /// Runs `transform` off the main thread, then swaps in the result as one undo step.
    /// Any selection is cleared, since its pixels may no longer line up.
    private func edit(
        _ message: String,
        resolution newResolution: ImageResolution? = nil,
        _ transform: @escaping @Sendable (RasterImage) throws -> RasterImage
    ) {
        guard let original = image, !isBusy else { return }
        let originalResolution = resolution
        run(message) {
            let result = try transform(original)
            await MainActor.run {
                self.undoStack.append(Snapshot(image: original, resolution: originalResolution))
                if self.undoStack.count > self.maxUndoSteps { self.undoStack.removeFirst() }
                self.redoStack.removeAll()
                self.image = result
                if let newResolution { self.resolution = newResolution }
                self.setSelection(nil)
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
