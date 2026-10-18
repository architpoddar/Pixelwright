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

    @State private var widthValue: Double
    @State private var heightValue: Double
    @State private var anchor: AnchorEdge = .middle
    @State private var fillChoice: FillChoice = .transparent
    @State private var customColor: Color = .white
    // Canvas Size remembers its own aspect setting, off by default (spec 2.1).
    @AppStorage("canvas.keepAspect") private var keepAspect = false

    init(original: RasterImage) {
        self.original = original
        _widthValue = State(initialValue: Double(original.width))
        _heightValue = State(initialValue: Double(original.height))
    }

    private var originalSize: (width: Int, height: Int) { (original.width, original.height) }
    private var newWidth: Int { SizeMath.roundToPixels(widthValue) }
    private var newHeight: Int { SizeMath.roundToPixels(heightValue) }
    private var isValid: Bool { SizeMath.isValid(width: newWidth, height: newHeight) }

    private var fill: CanvasFill {
        switch fillChoice {
        case .transparent: .transparent
        case .white: .white
        case .black: .black
        case .color: .primary(customColor.rgba8)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Canvas Size").font(.title2.bold())
            Text("Current size: \(original.width) × \(original.height) px")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Width:")
                    TextField("", value: widthBinding, format: .number.grouping(.never)).frame(width: 90)
                    Text("pixels")
                }
                GridRow {
                    Text("Height:")
                    TextField("", value: heightBinding, format: .number.grouping(.never)).frame(width: 90)
                    Text("pixels")
                }
            }
            Toggle("Maintain aspect ratio", isOn: $keepAspect)

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

            Text(isValid
                 ? "New size: \(newWidth) × \(newHeight) px"
                 : "Size must be between 1 and 262,144 px on each side.")
                .foregroundStyle(isValid ? Color.primary : Color.red)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    model.resizeCanvas(width: newWidth, height: newHeight, anchor: anchor, fill: fill)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private var widthBinding: Binding<Int> {
        Binding(
            get: { newWidth },
            set: { value in
                widthValue = Double(value)
                if keepAspect { heightValue = SizeMath.height(forWidth: widthValue, original: originalSize) }
            }
        )
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { newHeight },
            set: { value in
                heightValue = Double(value)
                if keepAspect { widthValue = SizeMath.width(forHeight: heightValue, original: originalSize) }
            }
        )
    }
}

/// 3x3 grid of anchor buttons.
struct AnchorGrid: View {
    @Binding var selection: AnchorEdge

    private let arrows = ["arrow.up.left", "arrow.up", "arrow.up.right",
                          "arrow.left", "circle.fill", "arrow.right",
                          "arrow.down.left", "arrow.down", "arrow.down.right"]

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
                        .help(String(describing: edge))
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
