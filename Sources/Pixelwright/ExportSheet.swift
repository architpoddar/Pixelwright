import PixelwrightCore
import SwiftUI

/// File > Export…: pick a format, set the quality and an optional size limit, see the file size.
struct ExportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("export.format") private var formatRaw = ExportFormat.png.rawValue
    @AppStorage("export.quality") private var quality = 85.0
    @AppStorage("export.limit") private var limitSize = false
    @AppStorage("export.maxSide") private var maxSide = 2048

    @State private var estimate: Int?
    @State private var estimating = false

    private var format: ExportFormat { ExportFormat(rawValue: formatRaw) ?? .png }

    private var longestSide: Int { max(model.image?.width ?? 0, model.image?.height ?? 0) }
    private var effectiveMaxSide: Int? { limitSize && maxSide > 0 && maxSide < longestSide ? maxSide : nil }

    /// Changes whenever the estimate needs recomputing.
    private var estimateKey: String { "\(formatRaw)-\(Int(quality))-\(effectiveMaxSide ?? 0)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.title2.bold())

            Picker("Format", selection: $formatRaw) {
                ForEach(ExportFormat.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .help("PNG and TIFF keep every pixel exactly. JPEG and HEIC make smaller files by discarding a little detail.")

            if format.supportsQuality {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Quality")
                        Spacer()
                        Text("\(Int(quality))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $quality, in: 10...100, step: 1)
                        .help("Higher quality looks better but makes a bigger file. 80 to 90 is a good balance.")
                }
            } else {
                Text(format == .png ? "PNG is lossless and keeps transparency." : "TIFF is lossless and keeps transparency.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Toggle("Limit the longest side to", isOn: $limitSize)
                .help("Shrinks big pictures on the way out, handy for email and websites. Your open picture isn't changed.")
            if limitSize {
                HStack {
                    TextField("", value: $maxSide, format: .number.grouping(.never))
                        .frame(width: 90)
                    Text("pixels")
                    if let image = model.image {
                        Spacer()
                        Text("now \(image.width) × \(image.height)").foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Text("Estimated size")
                Spacer()
                if let estimate {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(estimate), countStyle: .file))
                        .monospacedDigit()
                } else if estimating {
                    ProgressView().controlSize(.small)
                }
            }
            if format == .jpeg, model.image != nil {
                Text("JPEG has no transparency; see-through areas become white.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    dismiss()
                    model.export(format: format, quality: quality / 100, maxSide: effectiveMaxSide)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .task(id: estimateKey) {
            estimating = true
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
            estimate = await model.estimateExportSize(format: format, quality: quality / 100, maxSide: effectiveMaxSide)
            estimating = false
        }
    }
}
