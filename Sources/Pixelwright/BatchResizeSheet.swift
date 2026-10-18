import PixelwrightCore
import SwiftUI
import UniformTypeIdentifiers

/// Resizes many images in one go and saves the copies to a folder. The originals aren't touched.
@MainActor
final class BatchJob: ObservableObject {
    @Published var files: [URL] = []
    @Published var outputFolder: URL?
    @Published private(set) var done = 0
    @Published private(set) var isRunning = false
    @Published private(set) var failures: [String] = []
    @Published private(set) var summary: String?

    struct Settings: Sendable {
        var mode: BatchResizeMode
        var allowEnlarging: Bool
        var method: ResamplingMethod
        var gamma: Bool
        var format: ExportFormat?   // nil = keep each file's own format
        var quality: Double
        var suffix: String
    }

    private var task: Task<Void, Never>?

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose the images to resize"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        files = panel.urls
        summary = nil
        if outputFolder == nil, let first = panel.urls.first {
            outputFolder = first.deletingLastPathComponent().appendingPathComponent("Resized", isDirectory: true)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose where the resized copies are saved"
        if panel.runModal() == .OK { outputFolder = panel.url }
    }

    func start(_ settings: Settings) {
        guard let folder = outputFolder, !files.isEmpty, !isRunning else { return }
        let files = self.files
        isRunning = true
        done = 0
        failures = []
        summary = nil
        task = Task {
            var made = 0
            var failed: [String] = []
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
                failures = ["Couldn't create the output folder: \(error.localizedDescription)"]
                isRunning = false
                return
            }
            for url in files {
                if Task.isCancelled { break }
                let outcome: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                    Result { try Self.process(url, into: folder, settings: settings) }
                }.value
                switch outcome {
                case .success: made += 1
                case .failure(let error): failed.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                done += 1
            }
            failures = failed
            summary = Task.isCancelled
                ? "Stopped after \(made) of \(files.count) images."
                : "Resized \(made) of \(files.count) images" + (failed.isEmpty ? "." : ", \(failed.count) failed.")
            isRunning = false
        }
    }

    func cancel() { task?.cancel() }

    /// Loads, resizes and saves one image. Runs off the main thread.
    nonisolated static func process(_ url: URL, into folder: URL, settings: Settings) throws {
        let loaded = try RasterImage.load(from: url)
        let size = settings.mode.targetSize(
            width: loaded.image.width, height: loaded.image.height, allowEnlarging: settings.allowEnlarging)
        let resized = Resampler.resize(
            loaded.image, width: size.width, height: size.height, method: settings.method, gammaCorrect: settings.gamma)
        let format = settings.format ?? ExportFormat(pathExtension: url.pathExtension) ?? .png
        let name = BatchNaming.outputName(for: url.lastPathComponent, suffix: settings.suffix, fileExtension: format.fileExtension)
        let unique = BatchNaming.uniqueName(name) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        try resized.write(to: folder.appendingPathComponent(unique), format: format, quality: settings.quality, resolution: loaded.resolution)
    }
}

struct BatchResizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var job = BatchJob()

    private enum SizeKind: String, CaseIterable, Identifiable {
        case longest = "Longest side"
        case box = "Fit in a box"
        case percent = "Percentage"
        var id: String { rawValue }
    }

    @AppStorage("batch.kind") private var kindRaw = SizeKind.longest.rawValue
    @AppStorage("batch.longest") private var longest = 1600
    @AppStorage("batch.boxW") private var boxWidth = 1920
    @AppStorage("batch.boxH") private var boxHeight = 1080
    @AppStorage("batch.percent") private var percent = 50.0
    @AppStorage("batch.enlarge") private var allowEnlarging = false
    @AppStorage("batch.method") private var methodIndex = 0
    @AppStorage("batch.gamma") private var gamma = true
    @AppStorage("batch.format") private var formatRaw = "same"
    @AppStorage("batch.quality") private var quality = 85.0
    @AppStorage("batch.suffix") private var suffix = "-resized"

    private var kind: SizeKind { SizeKind(rawValue: kindRaw) ?? .longest }
    private var method: ResamplingMethod {
        ResamplingMethod.allCases.indices.contains(methodIndex) ? ResamplingMethod.allCases[methodIndex] : .bicubic
    }
    private var format: ExportFormat? { ExportFormat(rawValue: formatRaw) }

    private var mode: BatchResizeMode {
        switch kind {
        case .longest: .longestSide(pixels: longest)
        case .box: .fitWithin(maxWidth: boxWidth, maxHeight: boxHeight)
        case .percent: .percentage(percent)
        }
    }

    private var canStart: Bool { !job.files.isEmpty && job.outputFolder != nil && mode.isValid && !job.isRunning }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Batch Resize").font(.title2.bold())
                    Text("Resizes copies of your images. The originals aren't changed.")
                        .foregroundStyle(.secondary)

                    GroupBox("Images") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button("Choose Images…") { job.chooseFiles() }
                                Text(job.files.isEmpty ? "None chosen" : "\(job.files.count) chosen")
                                    .foregroundStyle(.secondary)
                            }
                            if !job.files.isEmpty {
                                Text(job.files.prefix(4).map(\.lastPathComponent).joined(separator: ", ")
                                     + (job.files.count > 4 ? ", …" : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            HStack {
                                Button("Save To…") { job.chooseFolder() }
                                Text(job.outputFolder?.path(percentEncoded: false) ?? "Choose a folder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }

                    GroupBox("Size") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $kindRaw) {
                                ForEach(SizeKind.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            switch kind {
                            case .longest:
                                HStack {
                                    TextField("", value: $longest, format: .number.grouping(.never)).frame(width: 90)
                                    Text("pixels on the longer side")
                                }
                            case .box:
                                HStack {
                                    TextField("", value: $boxWidth, format: .number.grouping(.never)).frame(width: 80)
                                    Text("×")
                                    TextField("", value: $boxHeight, format: .number.grouping(.never)).frame(width: 80)
                                    Text("pixels, at most")
                                }
                            case .percent:
                                HStack {
                                    TextField("", value: $percent, format: .number.precision(.fractionLength(0...2))).frame(width: 80)
                                    Text("% of the original size")
                                }
                            }
                            Toggle("Allow enlarging smaller images", isOn: $allowEnlarging)
                                .help("Off: pictures already smaller than the target are saved as they are, not blown up.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }

                    GroupBox("Output") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Resampling", selection: $methodIndex) {
                                ForEach(Array(ResamplingMethod.allCases.enumerated()), id: \.offset) { i, m in
                                    Text(m.displayName).tag(i)
                                }
                            }
                            Toggle("Use gamma correction", isOn: $gamma)
                                .disabled(!method.supportsGammaCorrection)
                            Picker("Format", selection: $formatRaw) {
                                Text("Same as original").tag("same")
                                ForEach(ExportFormat.allCases) { Text($0.displayName).tag($0.rawValue) }
                            }
                            if format?.supportsQuality ?? true {
                                HStack {
                                    Text("JPEG / HEIC quality")
                                    Slider(value: $quality, in: 10...100, step: 1)
                                    Text("\(Int(quality))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                                }
                            }
                            HStack {
                                Text("Add to file name")
                                TextField("", text: $suffix).frame(width: 120)
                                    .help("Added to each file name, so \"photo.jpg\" becomes \"photo-resized.jpg\". Existing files are never overwritten.")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }

                    if job.isRunning || job.summary != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            if job.isRunning {
                                ProgressView(value: Double(job.done), total: Double(max(1, job.files.count)))
                                Text("Resizing \(job.done + 1) of \(job.files.count)…").font(.callout)
                            }
                            if let summary = job.summary { Text(summary).font(.callout.bold()) }
                            ForEach(job.failures, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                        }
                    }
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            HStack {
                if job.summary != nil, let folder = job.outputFolder {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                }
                Spacer()
                if job.isRunning {
                    Button("Stop") { job.cancel() }
                } else {
                    Button(job.summary == nil ? "Cancel" : "Done", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(job.files.isEmpty ? "Resize Images" : "Resize \(job.files.count) Image\(job.files.count == 1 ? "" : "s")") {
                        job.start(.init(
                            mode: mode, allowEnlarging: allowEnlarging, method: method, gamma: gamma,
                            format: format, quality: quality / 100, suffix: suffix))
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
                }
            }
            .padding(12)
        }
        .frame(width: 440)
        .frame(minHeight: 360, idealHeight: 620, maxHeight: 720)
    }
}
