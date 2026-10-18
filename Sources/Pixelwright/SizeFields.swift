import PixelwrightCore
import SwiftUI

/// Pixel size, print size and resolution, shared by the Resize and Canvas Size dialogs.
/// All the arithmetic lives in `SizeEditorState`; this view only binds fields to it.
struct SizeFields: View {
    @Binding var state: SizeEditorState
    /// Dim the pixel and print fields (Resize does this while "By percentage" is chosen).
    var fieldsEnabled = true

    @AppStorage("sizeFields.showPrint") private var showPrint = false

    private static let printFormat = FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.fractionLength(0...3))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Pixel size") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("Width:")
                        TextField("", value: Binding(get: { state.pixelWidth }, set: { state.setPixelWidth($0) }),
                                  format: .number.grouping(.never))
                            .frame(width: 90)
                        Text("pixels")
                    }
                    GridRow {
                        Text("Height:")
                        TextField("", value: Binding(get: { state.pixelHeight }, set: { state.setPixelHeight($0) }),
                                  format: .number.grouping(.never))
                            .frame(width: 90)
                        Text("pixels")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            DisclosureGroup("Print size and resolution", isExpanded: $showPrint) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("Width:")
                        TextField("", value: Binding(get: { state.printWidth }, set: { state.setPrintWidth($0) }),
                                  format: Self.printFormat)
                            .frame(width: 90)
                        unitPicker
                    }
                    GridRow {
                        Text("Height:")
                        TextField("", value: Binding(get: { state.printHeight }, set: { state.setPrintHeight($0) }),
                                  format: Self.printFormat)
                            .frame(width: 90)
                        Text(state.unit.displayName)
                    }
                    GridRow {
                        Text("Resolution:")
                        TextField("", value: Binding(get: { state.resolution.pixelsPerUnit }, set: { state.setResolution($0) }),
                                  format: Self.printFormat)
                            .frame(width: 90)
                        Text(state.unit.resolutionLabel)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }

            Toggle("Maintain aspect ratio", isOn: $state.keepAspect)
        }
        .disabled(!fieldsEnabled)
    }

    private var unitPicker: some View {
        Picker("", selection: Binding(get: { state.unit }, set: { state.setUnit($0) })) {
            ForEach(MeasurementUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .labelsHidden()
        .frame(width: 120)
    }
}
