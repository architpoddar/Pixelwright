import PixelwrightCore
import SwiftUI

struct CanvasSizeSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let original: RasterImage

    private enum FillChoice: String, CaseIterable, Identifiable {
        case transparent = "Transparent"
        case white = "White"
        case black = "Black"
        case color = "Color"
        var id: String { rawValue }
    }

    @State private var size: SizeEditorState
    @State private var anchor: AnchorEdge = .middle
    @State private var fillChoice: FillChoice = .transparent
    @State private var customColor: Color = .white
    // Canvas Size remembers its own aspect setting, off by default (spec 2.1).
    @AppStorage("canvas.keepAspect") private var keepAspect = false

    init(original: RasterImage, resolution: ImageResolution) {
        self.original = original
        _size = State(
            initialValue: SizeEditorState(
                originalWidth: original.width, originalHeight: original.height,
                resolution: resolution, keepAspect: UserDefaults.standard.bool(forKey: "canvas.keepAspect")))
    }

    private var fill: CanvasFill {
        switch fillChoice {
        case .transparent: .transparent
        case .white: .white
        case .black: .black
        case .color: .primary(customColor.rgba8)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Canvas Size").font(.title2.bold())
                    Text("Current size: \(original.width) × \(original.height) px")
                        .foregroundStyle(.secondary)

                    SizeFields(state: $size)

                    Divider()

                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Anchor:")
                            AnchorGrid(selection: $anchor)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fill:")
                            Picker("", selection: $fillChoice) {
                                ForEach(FillChoice.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 130)
                            .help("What fills the new space when the canvas gets bigger. Transparent keeps it see-through.")
                            if fillChoice == .color {
                                ColorPicker("Color", selection: $customColor, supportsOpacity: true)
                            }
                            Text("Only used when the canvas gets bigger.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(
                        size.isValid
                            ? "New size: \(size.pixelWidth) × \(size.pixelHeight) px"
                            : "Size must be 1 to 262,144 px per side, with a resolution of at least 0.01."
                    )
                    .foregroundStyle(size.isValid ? Color.primary : Color.red)

                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    model.resizeCanvas(
                        width: size.pixelWidth, height: size.pixelHeight,
                        anchor: anchor, fill: fill, resolution: size.resolution)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!size.isValid)
            }
            .padding(12)
        }
        .frame(width: 360)
        .frame(minHeight: 320, idealHeight: 580, maxHeight: 700)
        .onChange(of: size.keepAspect) { _, newValue in keepAspect = newValue }
    }
}

/// 3x3 grid of anchor buttons.
struct AnchorGrid: View {
    @Binding var selection: AnchorEdge

    private let arrows = [
        "arrow.up.left", "arrow.up", "arrow.up.right",
        "arrow.left", "circle.fill", "arrow.right",
        "arrow.down.left", "arrow.down", "arrow.down.right",
    ]

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        let edge = AnchorEdge(rawValue: row * 3 + col)!
                        Button {
                            selection = edge
                        } label: {
                            Image(systemName: selection == edge ? "square.fill" : arrows[row * 3 + col])
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .tint(selection == edge ? .accentColor : nil)
                        .help("Keep the picture at the \(edge.displayName.lowercased()). The canvas grows or shrinks from the opposite side.")
                        .accessibilityLabel(edge.displayName)
                    }
                }
            }
        }
    }
}

extension Color {
    /// Straight-alpha sRGB bytes for the engine.
    var rgba8: RGBA8 {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return RGBA8(r: byte(ns.redComponent), g: byte(ns.greenComponent), b: byte(ns.blueComponent), a: byte(ns.alphaComponent))
    }
}
