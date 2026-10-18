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
                    CanvasView(image: image, zoom: zoom)
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
            }
        }
        .navigationTitle(model.fileName)
        .sheet(isPresented: $model.showingResize) {
            if let image = model.image { ResizeSheet(original: image) }
        }
        .sheet(isPresented: $model.showingCanvasSize) {
            if let image = model.image { CanvasSizeSheet(original: image) }
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

    private var statusBar: some View {
        HStack {
            if let image = model.image {
                Text("\(image.width) × \(image.height) px")
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

/// Shows the image on a checkerboard so transparency is visible.
struct CanvasView: View {
    let image: RasterImage
    let zoom: Double?

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
                }
                .frame(width: w, height: h)
                .shadow(radius: 3)
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
