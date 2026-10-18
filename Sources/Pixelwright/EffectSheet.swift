import PixelwrightCore
import SwiftUI

/// A dialog with a few sliders and a live preview on the canvas behind it.
struct EffectSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let kind: EffectKind
    @State private var values: [Double]

    init(kind: EffectKind) {
        self.kind = kind
        _values = State(initialValue: kind.defaultValues)
    }

    private var effect: Effect { kind.effect(values: values) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind.title).font(.title2.bold())

            if model.hasSelection {
                Label("Applies to the selection only", systemImage: "selection.pin.in.out")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(kind.sliders.enumerated()), id: \.offset) { index, spec in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(spec.label)
                        Spacer()
                        Text("\(Int(values[index]))\(spec.unit)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $values[index], in: spec.range, step: spec.step)
                }
            }

            HStack {
                Button("Reset") { values = kind.defaultValues }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    model.applyEffect(effect)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { model.requestPreview(effect) }
        .onChange(of: values) { _, _ in model.requestPreview(effect) }
        .onDisappear { model.clearPreview() }
    }
}
