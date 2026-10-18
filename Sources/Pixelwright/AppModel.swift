import AppKit
import PixelwrightCore
import SwiftUI
import UniformTypeIdentifiers

enum Tool: Equatable {
    case none
    case rectangleSelect
    case lasso
    case magicWand

    var isSelectionTool: Bool { self != .none }
}

enum EditError: LocalizedError {
    case nothingToCrop
    case fullyTransparent

    var errorDescription: String? {
        switch self {
        case .nothingToCrop: "Select an area first, then choose Crop to Selection."
        case .fullyTransparent: "The image is completely transparent, so there is nothing to crop to."
        }
    }
}

/// One open image with simple snapshot-based undo/redo.
@MainActor
final class AppModel: ObservableObject {
    /// The one model, shared so the app delegate can ask about unsaved changes when quitting.
    static let shared = AppModel()

    /// What undo restores: the pixels and the resolution they were saved with.
    private struct Snapshot {
        let image: RasterImage
        let resolution: ImageResolution
        /// Which version of the image this is, so we can tell if the current one has been saved.
        let stateID: UUID
    }

    @Published private(set) var image: RasterImage? {
        didSet { imageCG = image?.makeCGImage() }
    }
    /// The image as a CGImage, kept ready so repaints don't convert it again.
    @Published private(set) var imageCG: CGImage?
    /// A live preview of an effect while its dialog is open (nil otherwise).
    @Published private(set) var previewCG: CGImage?
    @Published var effectSheet: EffectKind?
    @Published var showingExport = false
    @Published var showingBatch = false
    @Published private(set) var resolution: ImageResolution = .default
    @Published private(set) var fileName: String = "Untitled"
    /// The file the image was opened from. Pixelwright only ever reads it.
    @Published private(set) var sourceURL: URL?
    /// A short confirmation after saving, shown briefly in the status bar.
    @Published private(set) var notice: Notice?
    @Published private(set) var stateID = UUID()
    @Published private(set) var savedStateID = UUID()
    @Published private(set) var isBusy = false
    @Published private(set) var busyMessage = ""
    @Published var errorMessage: String?
    @Published var showingResize = false
    @Published var showingCanvasSize = false

    // Selection and the Magic Wand
    @Published var tool: Tool = .none
    @Published var wandTolerance: Double = 25
    @Published var wandMode: MagicWandMode = .contiguous
    /// How softly Delete fades the edge of a selection, in pixels (0 = hard edge).
    @Published var featherRadius: Double = 0
    @Published private(set) var selection: SelectionMask?
    @Published private(set) var selectionOverlay: CGImage?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let maxUndoSteps = 20

    /// What the canvas shows: the live preview if there is one, otherwise the image.
    var displayCG: CGImage? { previewCG ?? imageCG }

    var hasImage: Bool { image != nil }
    var canUndo: Bool { !undoStack.isEmpty && !isBusy }
    var canRedo: Bool { !redoStack.isEmpty && !isBusy }
    var canEdit: Bool { hasImage && !isBusy }
    var hasSelection: Bool { selection != nil }
    /// True when the picture has changes that haven't been saved to a copy.
    var isEdited: Bool { hasImage && stateID != savedStateID }

    struct Notice: Equatable {
        let text: String
        let revealURL: URL?
    }

    // MARK: Files

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard confirmDiscardIfNeeded(action: "open another image") else { return }
        run("Opening…") {
            let loaded = try RasterImage.load(from: url)
            await MainActor.run {
                self.image = loaded.image
                self.resolution = loaded.resolution
                self.fileName = url.lastPathComponent
                self.sourceURL = url
                self.undoStack.removeAll()
                self.redoStack.removeAll()
                self.stateID = UUID()
                self.savedStateID = self.stateID
                self.notice = nil
                self.setSelection(nil)
            }
        }
    }

    /// Forgets the open image (when its window is closed).
    func closeImage() {
        image = nil
        sourceURL = nil
        fileName = "Untitled"
        undoStack.removeAll()
        redoStack.removeAll()
        stateID = UUID()
        savedStateID = stateID
        notice = nil
        tool = .none
        setSelection(nil)
    }

    // MARK: Saving copies
    //
    // Pixelwright never changes the file an image was opened from. Edits happen in memory; saving
    // always writes a new file. Replacing the original is possible, but only after an explicit warning.

    /// File > Save a Copy…
    func saveCopy() {
        guard image != nil else { return }
        _ = saveCopyNow()
    }

    /// Asks where to save, then writes a copy right away. Returns true if a file was written.
    @discardableResult
    private func saveCopyNow() -> Bool {
        guard let image else { return false }
        let format = defaultFormat
        guard let url = chooseDestination(format: format) else { return false }
        do {
            try image.write(to: url, format: ExportFormat(pathExtension: url.pathExtension) ?? format, resolution: resolution)
            didSave(to: url)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Saving keeps the original's format where we can write it, otherwise PNG.
    private var defaultFormat: ExportFormat {
        sourceURL.flatMap { ExportFormat(pathExtension: $0.pathExtension) } ?? .png
    }

    private func didSave(to url: URL) {
        savedStateID = stateID
        notice = Notice(text: "Saved a copy: \(url.lastPathComponent)", revealURL: url)
        Task {
            try? await Task.sleep(for: .seconds(8))
            if notice?.revealURL == url { notice = nil }
        }
    }

    /// The save panel, set up so the safe choice is the easy one: it opens in the original's folder
    /// with a name that can't collide, says plainly that a copy is saved, and stops to ask before
    /// anything would replace the original file.
    private func chooseDestination(format: ExportFormat) -> URL? {
        let folder = sourceURL?.deletingLastPathComponent()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        if format == defaultFormat { panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic] }
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Save Copy"
        panel.message = "Pixelwright saves a copy. Your original file is never changed."
        panel.nameFieldStringValue = SaveNaming.suggestedCopyName(
            original: sourceURL?.lastPathComponent, fileExtension: format.fileExtension,
            exists: { name in folder.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(name).path) } ?? false })

        guard panel.runModal() == .OK, var url = panel.url else { return nil }
        if let source = sourceURL, Self.isSameFile(url, source) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "That would replace your original file"
            alert.informativeText = "“\(source.lastPathComponent)” is the file you opened. Pixelwright works on a copy so your original stays safe. Save a copy next to it instead?"
            alert.addButton(withTitle: "Save a Copy Instead")
            alert.addButton(withTitle: "Replace Original")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let name = SaveNaming.suggestedCopyName(
                    original: source.lastPathComponent, fileExtension: url.pathExtension.isEmpty ? format.fileExtension : url.pathExtension,
                    exists: { FileManager.default.fileExists(atPath: source.deletingLastPathComponent().appendingPathComponent($0).path) })
                url = source.deletingLastPathComponent().appendingPathComponent(name)
            case .alertSecondButtonReturn:
                break  // the user confirmed: write over the original
            default:
                return nil
            }
        }
        return url
    }

    /// True if both URLs point at the same file (macOS volumes ignore upper and lower case by default).
    nonisolated static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let x = try? a.resourceValues(forKeys: keys).fileResourceIdentifier,
           let y = try? b.resourceValues(forKeys: keys).fileResourceIdentifier {
            return (x as AnyObject).isEqual(y)
        }
        return a.standardizedFileURL.path.lowercased() == b.standardizedFileURL.path.lowercased()
    }

    /// Before the image is discarded (closing the window, quitting, opening another), offers to save
    /// a copy. Returns true if it is fine to go ahead.
    func confirmDiscardIfNeeded(action: String) -> Bool {
        guard isEdited else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save a copy of “\(fileName)” before you \(action)?"
        alert.informativeText = "Your changes haven't been saved. The original file stays exactly as it is."
        alert.addButton(withTitle: "Save a Copy…")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveCopyNow()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    // MARK: Export

    /// The image as it would be exported: shrunk to `maxSide` on its longer side if given.
    nonisolated private static func exportData(
        _ image: RasterImage, resolution: ImageResolution, format: ExportFormat, quality: Double, maxSide: Int?
    ) throws -> Data {
        var source = image
        if let maxSide, max(image.width, image.height) > maxSide {
            let size = BatchResizeMode.longestSide(pixels: maxSide)
                .targetSize(width: image.width, height: image.height, allowEnlarging: false)
            source = Resampler.resize(image, width: size.width, height: size.height, method: .bicubic, gammaCorrect: true)
        }
        return try source.encoded(as: format, quality: quality, resolution: resolution)
    }

    /// How big the exported file would be, in bytes (nil if it can't be worked out).
    func estimateExportSize(format: ExportFormat, quality: Double, maxSide: Int?) async -> Int? {
        guard let image else { return nil }
        let resolution = self.resolution
        return await Task.detached(priority: .utility) {
            try? Self.exportData(image, resolution: resolution, format: format, quality: quality, maxSide: maxSide).count
        }.value
    }

    func export(format: ExportFormat, quality: Double, maxSide: Int?) {
        guard let image else { return }
        let resolution = self.resolution
        guard let url = chooseDestination(format: format) else { return }
        run("Exporting…") {
            let data = try Self.exportData(image, resolution: resolution, format: format, quality: quality, maxSide: maxSide)
            try data.write(to: url)
            await MainActor.run { self.didSave(to: url) }
        }
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
        let feather = Int(featherRadius)
        edit("Deleting selection…") { image in image.clearingPixels(in: mask, feather: feather) }
    }

    // MARK: Adjustments and effects

    /// Applies an effect to the selection, or to the whole image if nothing is selected.
    func applyEffect(_ effect: Effect) {
        guard !effect.isIdentity else { return }
        let mask = selection
        edit("Applying…", keepSelection: true) { image in image.applying(effect, within: mask) }
    }

    private var previewTask: Task<Void, Never>?

    /// Shows what `effect` would do, on a smaller copy so it keeps up with a slider.
    func requestPreview(_ effect: Effect) {
        previewTask?.cancel()
        guard let image else { return }
        let mask = selection
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { return }
            let cg: CGImage? = await Task.detached(priority: .userInitiated) {
                let (small, factor) = image.previewCopy(maxDimension: 1200)
                let smallMask = mask.map { factor == 1 ? $0 : $0.resized(width: small.width, height: small.height) }
                return small.applying(effect.scaled(by: factor), within: smallMask).makeCGImage()
            }.value
            if !Task.isCancelled { previewCG = cg }
        }
    }

    func clearPreview() {
        previewTask?.cancel()
        previewCG = nil
    }

    // MARK: Crop, rotate, flip

    func rotate(_ rotation: Rotation) {
        edit("Rotating…") { ImageTransform.rotated($0, rotation) }
    }

    func flipHorizontally() {
        edit("Flipping…") { ImageTransform.flippedHorizontally($0) }
    }

    func flipVertically() {
        edit("Flipping…") { ImageTransform.flippedVertically($0) }
    }

    /// Crops to the selection's bounds, cutting out its shape if it isn't a rectangle.
    func cropToSelection() {
        guard let mask = selection else {
            errorMessage = EditError.nothingToCrop.errorDescription
            return
        }
        edit("Cropping…") { image in
            guard let cropped = image.croppedToSelection(mask) else { throw EditError.nothingToCrop }
            return cropped
        }
    }

    /// Trims fully transparent borders.
    func autoCrop() {
        edit("Cropping…") { image in
            guard let cropped = ImageTransform.autoCropped(image) else { throw EditError.fullyTransparent }
            return cropped
        }
    }

    // MARK: Edit-menu commands
    //
    // Cut, Copy, Paste, Select All and Undo act on the image, except while a text field is being
    // edited (for example in the Resize dialog), where they keep their normal text behavior.

    private var editingText: NSText? { NSApp.keyWindow?.firstResponder as? NSText }

    func cutCommand() { if let t = editingText { t.cut(nil) } else { cutToClipboard() } }
    func copyCommand() { if let t = editingText { t.copy(nil) } else { copyToClipboard() } }
    func pasteCommand() { if let t = editingText { t.paste(nil) } else { pasteAsNewImage() } }
    func selectAllCommand() { if let t = editingText { t.selectAll(nil) } else { selectAll() } }
    func undoCommand() { if let t = editingText { t.undoManager?.undo() } else { undo() } }
    func redoCommand() { if let t = editingText { t.undoManager?.redo() } else { redo() } }

    var canUseEditCommand: Bool { editingText != nil || canEdit }
    var isSheetOpen: Bool { showingResize || showingCanvasSize || effectSheet != nil || showingExport || showingBatch }

    // MARK: Clipboard

    /// Copies the selection (cut out to its shape) or, with no selection, the whole image.
    func copyToClipboard() {
        guard let image else { return }
        let source = selection.flatMap { image.croppedToSelection($0) } ?? image
        guard let cg = source.makeCGImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: cg, size: NSSize(width: source.width, height: source.height))])
    }

    func cutToClipboard() {
        copyToClipboard()
        if hasSelection { deleteSelection() }
    }

    /// Replaces the open image with the one on the clipboard. Undoable.
    func pasteAsNewImage() {
        guard let nsImage = NSImage(pasteboard: .general),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let pasted = try? RasterImage(cgImage: cg)
        else {
            errorMessage = "The clipboard doesn't contain an image."
            return
        }
        if let current = image {
            undoStack.append(Snapshot(image: current, resolution: resolution, stateID: stateID))
            if undoStack.count > maxUndoSteps { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        image = pasted
        resolution = .default
        fileName = "Clipboard"
        sourceURL = nil
        stateID = UUID()  // new, unsaved picture: closing it should ask
        savedStateID = UUID()
        setSelection(nil)
    }

    func undo() {
        guard let current = image, let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(image: current, resolution: resolution, stateID: stateID))
        apply(previous)
    }

    func redo() {
        guard let current = image, let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(image: current, resolution: resolution, stateID: stateID))
        apply(next)
    }

    private func apply(_ snapshot: Snapshot) {
        image = snapshot.image
        resolution = snapshot.resolution
        stateID = snapshot.stateID
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
        let tolerance = wandTolerance, mode = wandMode
        Task {
            let picked = await Task.detached {
                MagicWand.select(in: image, x: x, y: y, tolerance: tolerance, mode: mode)
            }.value
            applySelection(picked, combine: combine)
        }
    }

    func selectRectangle(_ rect: PixelRect, combine: SelectionCombine) {
        guard let image, !isBusy else { return }
        applySelection(.rectangle(width: image.width, height: image.height, rect: rect), combine: combine)
    }

    func selectPolygon(_ points: [(x: Double, y: Double)], combine: SelectionCombine) {
        guard let image, !isBusy else { return }
        applySelection(.polygon(width: image.width, height: image.height, points: points), combine: combine)
    }

    /// Replaces, adds to or subtracts from the current selection.
    private func applySelection(_ picked: SelectionMask, combine: SelectionCombine) {
        switch combine {
        case .replace:
            setSelection(picked.isEmpty ? nil : picked)
        case .add:
            setSelection(selection.map { $0.union(picked) } ?? (picked.isEmpty ? nil : picked))
        case .subtract:
            if let current = selection {
                let result = current.subtracting(picked)
                setSelection(result.isEmpty ? nil : result)
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
        keepSelection: Bool = false,
        _ transform: @escaping @Sendable (RasterImage) throws -> RasterImage
    ) {
        guard let original = image, !isBusy else { return }
        let originalResolution = resolution
        run(message) {
            let result = try transform(original)
            await MainActor.run {
                self.undoStack.append(Snapshot(image: original, resolution: originalResolution, stateID: self.stateID))
                if self.undoStack.count > self.maxUndoSteps { self.undoStack.removeFirst() }
                self.redoStack.removeAll()
                self.stateID = UUID()
                self.image = result
                if let newResolution { self.resolution = newResolution }
                self.previewCG = nil
                if !keepSelection { self.setSelection(nil) }
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
