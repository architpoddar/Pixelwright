import AppKit
import PixelwrightCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    /// nil means "fit to window".
    @State private var zoom: Double?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if model.hasImage {
                    toolPalette
                    Divider()
                }
                canvasArea
            }

            Divider()
            if model.tool.isSelectionTool { toolBar; Divider() }
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { BrandChip() }
            ToolbarItemGroup {
                Button { model.openWithPanel() } label: { Label("Open", systemImage: "folder") }
                    .help("Open an image (⌘O). The file itself is never changed.")
                    .labelStyle(.titleAndIcon)
                Button { model.showingResize = true } label: {
                    Label("Resize", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Make the picture bigger or smaller, or change its print size (⌘R)")
                .labelStyle(.titleAndIcon)
                .disabled(!model.canEdit)
                Button { model.showingCanvasSize = true } label: { Label("Canvas", systemImage: "rectangle.expand.vertical") }
                    .help("Add or trim space around the picture without stretching it (⇧⌘R)")
                    .labelStyle(.titleAndIcon)
                    .disabled(!model.canEdit)
                Button { model.removeBackground() } label: { Label("Cut Out", systemImage: "person.crop.rectangle") }
                    .help("Remove Background: cut out the main subject automatically (⇧⌘B)")
                    .labelStyle(.titleAndIcon)
                    .disabled(!model.canEdit)
            }
        }
        .navigationTitle(model.hasImage ? model.fileName : "")
        .background(WindowAccessor(model: model, isEdited: model.isEdited, fileURL: model.sourceURL))
        .sheet(isPresented: $model.showingResize) {
            if let image = model.image { ResizeSheet(original: image, resolution: model.resolution) }
        }
        .sheet(isPresented: $model.showingCanvasSize) {
            if let image = model.image { CanvasSizeSheet(original: image, resolution: model.resolution) }
        }
        .sheet(item: $model.effectSheet) { kind in EffectSheet(kind: kind) }
        .sheet(isPresented: $model.showingExport) { ExportSheet() }
        .sheet(isPresented: $model.showingBatch) { BatchResizeSheet() }
        .tint(Brand.accent)
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// The picture (or the welcome screen), with a busy indicator and drag-and-drop.
    private var canvasArea: some View {
        ZStack {
            if let image = model.image {
                CanvasView(
                    image: image,
                    display: model.displayCG,
                    selectionOverlay: model.selectionOverlay,
                    zoom: zoom,
                    tool: model.tool,
                    onClick: { x, y in model.wandClick(x: x, y: y, combine: Self.combineMode()) },
                    onRectangle: { model.selectRectangle($0, combine: Self.combineMode()) },
                    onLasso: { model.selectPolygon($0, combine: Self.combineMode()) }
                )
            } else {
                WelcomeView()
            }
            if model.isBusy {
                ProgressView(model.busyMessage)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
    }

    /// The tools down the left edge, like a classic editor's toolbox.
    private var toolPalette: some View {
        VStack(spacing: 6) {
            toolButton(.none, "Pointer", "cursorarrow",
                       "Pointer: just look around. Turns the selection tools off (⇧⌘P)")
            toolButton(.rectangleSelect, "Rectangle Select", "rectangle.dashed",
                       "Rectangle Select: drag to select a box (⇧⌘M)")
            toolButton(.lasso, "Lasso Select", "lasso",
                       "Lasso Select: draw around any shape to select it (⇧⌘L)")
            toolButton(.magicWand, "Magic Wand", "wand.and.stars",
                       "Magic Wand: click to select pixels of a similar color (⇧⌘W)")
            Spacer()
            historyButton("arrow.uturn.backward", name: "Undo", tip: model.undoActionName.map { "Undo \($0) (⌘Z)" } ?? "Nothing to undo",
                          enabled: model.canUndo) { model.undo() }
            historyButton("arrow.uturn.forward", name: "Redo", tip: model.redoActionName.map { "Redo \($0) (⇧⌘Z)" } ?? "Nothing to redo",
                          enabled: model.canRedo) { model.redo() }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(width: 52)
        .background(.bar)
    }

    /// Two rows: what the tool does, then what you can do with the current selection.
    private var toolBar: some View {
        VStack(spacing: 0) {
            toolOptionsRow
            if let mask = model.selection {
                Divider()
                selectionActionsRow(mask)
            }
        }
    }

    /// Each row has a roomy layout, a compact one for narrower windows, and finally scrolls, so
    /// nothing is ever squashed or wrapped.
    private var toolOptionsRow: some View {
        ViewThatFits(in: .horizontal) {
            optionsRow(compact: false)
            optionsRow(compact: true)
            ScrollView(.horizontal, showsIndicators: false) { optionsRow(compact: true) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func optionsRow(compact: Bool) -> some View {
        HStack(spacing: 12) {
            switch model.tool {
            case .magicWand:
                Label("Magic Wand", systemImage: "wand.and.stars").font(.callout.bold())
                Text("Tolerance").foregroundStyle(.secondary)
                Slider(value: $model.wandTolerance, in: 0...100, step: 1)
                    .frame(width: compact ? 110 : 160)
                    .help("How different a color can be from the one you click and still be selected. Higher selects more.")
                Text("\(Int(model.wandTolerance))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                Picker("Mode", selection: $model.wandMode) {
                    ForEach(MagicWandMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .labelsHidden()
                .help("Flood fill selects only pixels connected to your click. Global selects every matching pixel in the picture.")
            case .rectangleSelect:
                Label("Rectangle Select", systemImage: "rectangle.dashed").font(.callout.bold())
                Text("Drag to select a rectangle").foregroundStyle(.secondary)
            case .lasso:
                Label("Lasso Select", systemImage: "lasso").font(.callout.bold())
                Text("Drag to draw around an area").foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }
            Spacer(minLength: 8)
            if !compact {
                Text("Shift adds, Option subtracts").foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: !compact, vertical: true)
        .lineLimit(1)
    }

    private func selectionActionsRow(_ mask: SelectionMask) -> some View {
        ViewThatFits(in: .horizontal) {
            actionsRow(mask, compact: false)
            actionsRow(mask, compact: true)
            ScrollView(.horizontal, showsIndicators: false) { actionsRow(mask, compact: true) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func actionsRow(_ mask: SelectionMask, compact: Bool) -> some View {
        HStack(spacing: 12) {
            Text(compact ? "\(mask.selectedCount.formatted()) px" : "\(mask.selectedCount.formatted()) px selected")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("Feather").foregroundStyle(.secondary)
            Slider(value: $model.featherRadius, in: 0...20, step: 1)
                .frame(width: compact ? 70 : 100)
                .help("Softens the edge when you press Delete, so a cut-out blends in. 0 gives a sharp edge.")
            Text("\(Int(model.featherRadius)) px")
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
            Button("Crop") { model.cropToSelection() }
                .help("Crop the picture to the selection (⇧⌘X). An irregular selection cuts out just its shape.")
            Button("Delete") { model.deleteSelection() }
                .help("Make the selected pixels transparent (Delete key)")
            Button("Deselect") { model.deselect() }
                .help("Clear the selection (⇧⌘A)")
        }
        .font(.callout)
        .fixedSize(horizontal: !compact, vertical: true)
        .lineLimit(1)
    }

    /// Shift adds to the selection and Option subtracts, whatever the tool.
    private static func combineMode() -> AppModel.SelectionCombine {
        let flags = NSEvent.modifierFlags
        return flags.contains(.shift) ? .add : flags.contains(.option) ? .subtract : .replace
    }

    /// Undo or Redo at the bottom of the palette, with a tooltip that names the action.
    private func historyButton(_ symbol: String, name: String, tip: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 36, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
        .disabled(!enabled)
        .help(tip)
        .accessibilityLabel(name)
    }

    /// One tool in the palette: lights up in the brand color while active, and has a tooltip.
    private func toolButton(_ tool: Tool, _ name: String, _ symbol: String, _ tip: String) -> some View {
        let active = model.tool == tool
        return Button {
            model.tool = active && tool != .none ? .none : tool
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(active ? Brand.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(tip)
        .accessibilityLabel(name)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var statusBar: some View {
        HStack {
            if let image = model.image {
                Text("\(image.width) × \(image.height) px")
                Text("·").foregroundStyle(.secondary)
                Text("\(model.resolution.pixelsPerUnit.formatted(.number.precision(.fractionLength(0...2)))) \(model.resolution.unit.resolutionLabel)")
                    .foregroundStyle(.secondary)
            }
            if let notice = model.notice {
                Text("·").foregroundStyle(.secondary)
                Label(notice.text, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                if let url = notice.revealURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.link)
                }
            }
            Spacer()
            if model.hasImage {
                Button("Fit") { zoom = nil }.buttonStyle(.link)
                    .help("Shrink the view so the whole picture fits in the window")
                Button("100%") { zoom = 1 }.buttonStyle(.link)
                    .help("Show the picture at actual size: one image pixel per screen pixel")
                Slider(value: Binding(get: { zoom ?? 1 }, set: { zoom = $0 }), in: 0.05...8)
                    .frame(width: 140)
                    .help("Zoom in and out")
                Text(zoom.map { "\(Int(($0 * 100).rounded()))%" } ?? "Fit")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// Shows the image on a checkerboard so transparency is visible, with the selection tinted on top.
/// One drag gesture serves every selection tool: a click for the wand, a rectangle, or a lasso path.
struct CanvasView: View {
    let image: RasterImage
    let display: CGImage?
    let selectionOverlay: CGImage?
    let zoom: Double?
    let tool: Tool
    /// A click while the Magic Wand is active, in image pixels.
    let onClick: (Int, Int) -> Void
    let onRectangle: (PixelRect) -> Void
    let onLasso: ([(x: Double, y: Double)]) -> Void

    /// Points of the drag in progress, in view coordinates.
    @State private var drag: [CGPoint] = []

    var body: some View {
        GeometryReader { geo in
            let fit = min(1, min((geo.size.width - 32) / Double(image.width), (geo.size.height - 32) / Double(image.height)))
            let scale = zoom ?? max(0.01, fit)
            let w = Double(image.width) * scale
            let h = Double(image.height) * scale
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    Checkerboard().frame(width: w, height: h)
                    if let cg = display {
                        Image(decorative: cg, scale: 1)
                            .resizable()
                            .interpolation(scale >= 1 ? .none : .high)
                            .frame(width: w, height: h)
                    }
                    if let overlay = selectionOverlay {
                        Image(decorative: overlay, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: w, height: h)
                            .allowsHitTesting(false)
                    }
                    outline.allowsHitTesting(false)
                }
                .frame(width: w, height: h)
                .shadow(radius: 3)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard tool.isSelectionTool else { return }
                            if drag.isEmpty { drag = [value.startLocation] }
                            if tool == .lasso { drag.append(value.location) } else { drag = [value.startLocation, value.location] }
                        }
                        .onEnded { value in
                            defer { drag = [] }
                            finish(drag: drag, end: value.location, scale: scale)
                        }
                )
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// The rubber band or lasso path while dragging.
    @ViewBuilder private var outline: some View {
        if drag.count >= 2 {
            let style = StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            if tool == .lasso {
                Path { p in p.addLines(drag) }
                    .stroke(Brand.coral, style: style)
                Path { p in p.addLines(drag); p.closeSubpath() }
                    .fill(Brand.coral.opacity(0.12))
            } else if let a = drag.first, let b = drag.last {
                Rectangle()
                    .fill(Brand.coral.opacity(0.12))
                    .overlay(Rectangle().stroke(Brand.coral, style: style))
                    .frame(width: abs(b.x - a.x), height: abs(b.y - a.y))
                    .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            }
        }
    }

    private func finish(drag points: [CGPoint], end: CGPoint, scale: Double) {
        guard let start = points.first else { return }
        let moved = hypot(end.x - start.x, end.y - start.y)
        switch tool {
        case .none:
            break
        case .magicWand:
            let x = Int(start.x / scale), y = Int(start.y / scale)
            if x >= 0, y >= 0, x < image.width, y < image.height { onClick(x, y) }
        case .rectangleSelect:
            guard moved >= 3 else { return }
            let x0 = min(start.x, end.x) / scale, x1 = max(start.x, end.x) / scale
            let y0 = min(start.y, end.y) / scale, y1 = max(start.y, end.y) / scale
            onRectangle(PixelRect(
                x: Int(x0.rounded(.down)), y: Int(y0.rounded(.down)),
                width: Int(x1.rounded(.up)) - Int(x0.rounded(.down)),
                height: Int(y1.rounded(.up)) - Int(y0.rounded(.down))))
        case .lasso:
            guard moved >= 3 || points.count > 4 else { return }
            onLasso(points.map { (x: $0.x / scale, y: $0.y / scale) })
        }
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            // Light base, then one dashed stroke per row for the dark squares (cheap even for big images).
            let cell: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.95)))
            for row in 0..<Int(ceil(size.height / cell)) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: CGFloat(row) * cell + cell / 2))
                line.addLine(to: CGPoint(x: size.width, y: CGFloat(row) * cell + cell / 2))
                context.stroke(
                    line,
                    with: .color(Color(white: 0.8)),
                    style: StrokeStyle(lineWidth: cell, dash: [cell, cell], dashPhase: row % 2 == 0 ? -cell : 0)
                )
            }
        }
    }
}
