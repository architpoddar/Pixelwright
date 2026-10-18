import PixelwrightCore
import SwiftUI

struct ResizeSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let original: RasterImage

    private enum Mode: Hashable { case percentage, absolute }

    @State private var mode: Mode = .absolute
    @State private var percent: Double = 100
    // Kept as doubles and only rounded when read as pixels (spec 1.2).
    @State private var widthValue: Double
    @State private var heightValue: Double
    @AppStorage("resize.keepAspect") private var keepAspect = true
    @AppStorage("resize.method") private var methodIndex = 0
    @AppStorage("resize.gamma") private var gamma = true

    init(original: RasterImage) {
        self.original = original
        _widthValue = State(initialValue: Double(original.width))
        _heightValue = State(initialValue: Double(original.height))
    }

    private var originalSize: (width: Int, height: Int) { (original.width, original.height) }
    private var method: ResamplingMethod {
        let all = ResamplingMethod.allCases
        return all.indices.contains(methodIndex) ? all[methodIndex] : .bicubic
    }
    private var newWidth: Int { SizeMath.roundToPixels(widthValue) }
    private var newHeight: Int { SizeMath.roundToPixels(heightValue) }
    private var isValid: Bool { SizeMath.isValid(width: newWidth, height: newHeight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resize").font(.title2.bold())

            Text("Current size: \(original.width) × \(original.height) px")
                .foregroundStyle(.secondary)

            Picker("", selection: $mode) {
                Text("By percentage").tag(Mode.percentage)
                Text("By absolute size").tag(Mode.absolute)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if mode == .percentage {
                HStack {
                    Text("Percentage:")
                    TextField("", value: percentBinding, format: .number.precision(.fractionLength(0...2)))
                        .frame(width: 80)
                    Text("%")
                }
            } else {
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
            }

            Divider()

            Picker("Resampling:", selection: $methodIndex) {
                ForEach(Array(ResamplingMethod.allCases.enumerated()), id: \.offset) { index, method in
                    Text(method.displayName).tag(index)
                }
            }
            .frame(width: 250)
            Toggle("Use gamma correction", isOn: $gamma)
                .disabled(!method.supportsGammaCorrection)

            Text(isValid
                 ? "New size: \(newWidth) × \(newHeight) px"
                 : "Size must be between 1 and 262,144 px on each side.")
                .foregroundStyle(isValid ? Color.primary : Color.red)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    model.resize(width: newWidth, height: newHeight, method: method, gamma: gamma)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    // MARK: Bindings that keep width, height and percentage in sync

    private var percentBinding: Binding<Double> {
        Binding(
            get: { percent },
            set: { newValue in
                percent = newValue
                // Each side is scaled and rounded independently.
                let size = SizeMath.size(percent: newValue, of: originalSize)
                widthValue = Double(size.width)
                heightValue = Double(size.height)
            }
        )
    }

    private var widthBinding: Binding<Int> {
        Binding(
            get: { newWidth },
            set: { value in
                widthValue = Double(value)
                if keepAspect { heightValue = SizeMath.height(forWidth: widthValue, original: originalSize) }
                percent = widthValue / Double(original.width) * 100
            }
        )
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { newHeight },
            set: { value in
                heightValue = Double(value)
                if keepAspect { widthValue = SizeMath.width(forHeight: heightValue, original: originalSize) }
                percent = widthValue / Double(original.width) * 100
            }
        )
    }
}
