import AppKit
import PixelwrightCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    /// nil means "fit to window".
    @State private var zoom: Double?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image = model.image {
                    CanvasView(
                        image: image,
                        selectionOverlay: model.selectionOverlay,
                        zoom: zoom,
                        wandActive: model.tool == .magicWand
                    ) { x, y in
                        let flags = NSEvent.modifierFlags
                        let combine: AppModel.SelectionCombine =
                            flags.contains(.shift) ? .add : flags.contains(.option) ? .subtract : .replace
                        model.wandClick(x: x, y: y, combine: combine)
                    }
                } else {
                    ContentUnavailableView(
                        "No image open",
                        systemImage: "photo.on.rectangle",
                        description: Text("Open an image with ⌘O, or drop one here.")
                    )
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

            Divider()
            if model.tool == .magicWand { wandBar; Divider() }
            statusBar
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Open", systemImage: "folder") { model.openWithPanel() }
                Button("Resize", systemImage: "arrow.up.left.and.arrow.down.right") { model.showingResize = true }
                    .disabled(!model.canEdit)
                Button("Canvas Size", systemImage: "rectangle.expand.vertical") { model.showingCanvasSize = true }
                    .disabled(!model.canEdit)
                Button("Remove Background", systemImage: "person.crop.rectangle") { model.removeBackground() }
                    .disabled(!model.canEdit)
                Toggle("Magic Wand", systemImage: "wand.and.stars", isOn: Binding(
                    get: { model.tool == .magicWand },
                    set: { model.tool = $0 ? .magicWand : .none }
                ))
                .disabled(!model.hasImage)
                .help("Magic Wand: click to select similar pixels. Shift adds, Option subtracts.")
            }
        }
        .navigationTitle(model.fileName)
        .sheet(isPresented: $model.showingResize) {
            if let image = model.image { ResizeSheet(original: image, resolution: model.resolution) }
        }
        .sheet(isPresented: $model.showingCanvasSize) {
            if let image = model.image { CanvasSizeSheet(original: image, resolution: model.resolution) }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var wandBar: some View {
        HStack(spacing: 12) {
            Label("Magic Wand", systemImage: "wand.and.stars").font(.callout.bold())
            Text("Tolerance")
            Slider(value: $model.wandTolerance, in: 0...100, step: 1)
                .frame(width: 160)
            Text("\(Int(model.wandTolerance))%")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            Picker("Mode", selection: $model.wandMode) {
                ForEach(MagicWandMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .labelsHidden()
            Spacer()
            if let mask = model.selection {
                Text("\(mask.selectedCount.formatted()) px selected")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Button("Delete") { model.deleteSelection() }
                Button("Deselect") { model.deselect() }
            } else {
                Text("Click the image to select").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var statusBar: some View {
        HStack {
            if let image = model.image {
                Text("\(image.width) × \(image.height) px")
                Text("·").foregroundStyle(.secondary)
                Text("\(model.resolution.pixelsPerUnit.formatted(.number.precision(.fractionLength(0...2)))) \(model.resolution.unit.resolutionLabel)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.hasImage {
                Button("Fit") { zoom = nil }.buttonStyle(.link)
                Button("100%") { zoom = 1 }.buttonStyle(.link)
                Slider(value: Binding(get: { zoom ?? 1 }, set: { zoom = $0 }), in: 0.05...8)
                    .frame(width: 140)
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
struct CanvasView: View {
    let image: RasterImage
    let selectionOverlay: CGImage?
    let zoom: Double?
    let wandActive: Bool
    /// Called with the image pixel under a click while the wand is active.
    let onWandClick: (Int, Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let fit = min(1, min((geo.size.width - 32) / Double(image.width), (geo.size.height - 32) / Double(image.height)))
            let scale = zoom ?? max(0.01, fit)
            let w = Double(image.width) * scale
            let h = Double(image.height) * scale
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    Checkerboard().frame(width: w, height: h)
                    if let cg = image.makeCGImage() {
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
                }
                .frame(width: w, height: h)
                .shadow(radius: 3)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    guard wandActive else { return }
                    let x = Int(tap.location.x / scale), y = Int(tap.location.y / scale)
                    guard x >= 0, y >= 0, x < image.width, y < image.height else { return }
                    onWandClick(x, y)
                })
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
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
