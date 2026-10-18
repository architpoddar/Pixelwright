import PixelwrightCore
import SwiftUI

struct ResizeSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let original: RasterImage

    private enum Mode: Hashable { case percentage, absolute }

    @State private var mode: Mode = .absolute
    @State private var size: SizeEditorState
    @AppStorage("resize.keepAspect") private var keepAspect = true
    @AppStorage("resize.method") private var methodIndex = 0
    @AppStorage("resize.gamma") private var gamma = true

    init(original: RasterImage, resolution: ImageResolution) {
        self.original = original
        _size = State(
            initialValue: SizeEditorState(
                originalWidth: original.width, originalHeight: original.height,
                resolution: resolution, keepAspect: UserDefaults.standard.object(forKey: "resize.keepAspect") as? Bool ?? true))
    }

    private var method: ResamplingMethod {
        let all = ResamplingMethod.allCases
        return all.indices.contains(methodIndex) ? all[methodIndex] : .bicubic
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
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

                    HStack {
                        Text("Percentage:")
                        TextField(
                            "", value: Binding(get: { size.percent }, set: { size.setPercent($0) }),
                            format: .number.grouping(.never).precision(.fractionLength(0...2))
                        )
                        .frame(width: 80)
                        Text("%")
                    }
                    .disabled(mode != .percentage)

                    SizeFields(state: $size, fieldsEnabled: mode == .absolute)

                    Divider()

                    Picker("Resampling:", selection: $methodIndex) {
                        ForEach(Array(ResamplingMethod.allCases.enumerated()), id: \.offset) { index, method in
                            Text(method.displayName).tag(index)
                        }
                    }
                    .frame(width: 270)
                    .help("How the new pixels are worked out. Bicubic is a good choice for most photos.")
                    Text(method.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Use gamma correction", isOn: $gamma)
                        .disabled(!method.supportsGammaCorrection)
                        .help(
                            "Resizes in linear light so brightness and color stay accurate when shrinking. Slightly slower. Not used by Nearest Neighbor."
                        )

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
                    model.resize(
                        width: size.pixelWidth, height: size.pixelHeight,
                        method: method, gamma: gamma, resolution: size.resolution)
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
