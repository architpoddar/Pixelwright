import SwiftUI

/// Pixelwright's identity: name, tagline, colors and the pixel "P" mark.
/// The same artwork is generated for the app icon by `scripts/make-icon.swift`; keep them in sync.
enum Brand {
    static let name = "Pixelwright"
    static let tagline = "Craft your pixels."
    static let repositoryURL = URL(string: "https://github.com/architpoddar/Pixelwright")!
    static let licenseName = "MIT License"

    static let indigo = Color(red: 0x43 / 255, green: 0x38 / 255, blue: 0xFF / 255)
    static let violet = Color(red: 0x7B / 255, green: 0x3F / 255, blue: 0xF2 / 255)
    static let coral = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x57 / 255)
    static let spark = Color(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x3F / 255)

    /// The signature indigo-to-coral diagonal gradient.
    static let gradient = LinearGradient(
        stops: [.init(color: indigo, location: 0), .init(color: violet, location: 0.5), .init(color: coral, location: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The color used for buttons, selections and highlights across the app.
    static let accent = violet

    /// 5 x 7 pixel "P". `S` marks the single spark pixel.
    fileprivate static let pattern = [
        "XXXX.",
        "X...S",
        "X...X",
        "XXXX.",
        "X....",
        "X....",
        "X....",
    ]

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        return "Version \(version)"
    }
}

/// The app icon's tile: gradient squircle with the pixel P. Scales to any size.
struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Brand.gradient)
            PixelP(cell: size * 0.0947)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: size * 0.06, y: size * 0.03)
    }
}

/// The P itself, drawn from a grid of rounded pixels.
private struct PixelP: View {
    let cell: CGFloat

    var body: some View {
        let gap = cell * 0.13
        VStack(spacing: gap) {
            ForEach(Array(Brand.pattern.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, ch in
                        RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous)
                            .fill(ch == "S" ? Brand.spark : Color.white)
                            .frame(width: cell, height: cell)
                            .opacity(ch == "." ? 0 : 1)
                    }
                }
            }
        }
    }
}

/// "Pixel" in a light weight, "wright" in a heavy coral weight.
struct Wordmark: View {
    var size: CGFloat = 28

    var body: some View {
        (Text("Pixel").font(.system(size: size, weight: .light))
            + Text("wright").font(.system(size: size, weight: .heavy)).foregroundColor(Brand.coral))
            .accessibilityLabel(Brand.name)
    }
}

/// A compact brand chip for the toolbar: mark and name.
struct BrandChip: View {
    var body: some View {
        HStack(spacing: 6) {
            BrandMark(size: 22)
            Wordmark(size: 15)
        }
        .padding(.horizontal, 4)
        .help("\(Brand.name): \(Brand.tagline)")
    }
}

/// Shown when no image is open.
struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: 128)
            Wordmark(size: 44)
            Text(Brand.tagline)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    model.openWithPanel()
                } label: {
                    Label("Open Image…", systemImage: "folder")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o")
                .help("Choose an image to edit (⌘O)")

                Button {
                    model.pasteAsNewImage()
                } label: {
                    Label("From Clipboard", systemImage: "doc.on.clipboard")
                        .frame(minWidth: 120)
                }
                .controlSize(.large)
                .help("Start from an image you copied (⌘V)")
            }
            .padding(.top, 6)

            Text("or drop an image anywhere in this window")
                .font(.callout)
                .foregroundStyle(.tertiary)

            Label("Your original files are never changed. Saving always makes a copy.", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .padding(40)
    }
}

/// The About window.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            BrandMark(size: 112)
            Wordmark(size: 36)
            Text(Brand.tagline).foregroundStyle(.secondary)
            Text(Brand.versionString)
                .font(.callout)
                .foregroundStyle(.tertiary)
            Divider().padding(.vertical, 4)
            Text("A free, open-source image editor for Mac.\nYour images never leave your computer,\nand your original files are never changed.")
                .multilineTextAlignment(.center)
                .font(.callout)
            Link("github.com/architpoddar/Pixelwright", destination: Brand.repositoryURL)
                .font(.callout)
            Text("Released under the \(Brand.licenseName).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 340)
    }
}

/// Help > Keyboard Shortcuts.
struct ShortcutsView: View {
    private struct Group: Identifiable {
        let id: String
        let rows: [(String, String)]
    }

    private let groups: [Group] = [
        Group(id: "File", rows: [
            ("Open…", "⌘O"), ("Save a Copy…", "⌘S"), ("Export…", "⇧⌘E"), ("Batch Resize…", "⌥⌘B"),
        ]),
        Group(id: "Edit", rows: [
            ("Undo", "⌘Z"), ("Redo", "⇧⌘Z"), ("Copy image or selection", "⌘C"), ("Cut", "⌘X"), ("Paste as new image", "⌘V"),
        ]),
        Group(id: "Image", rows: [
            ("Resize…", "⌘R"), ("Canvas Size…", "⇧⌘R"), ("Remove Background", "⇧⌘B"), ("Crop to Selection", "⇧⌘X"),
            ("Rotate 90° clockwise", "⌘]"), ("Rotate 90° counterclockwise", "⌘["),
        ]),
        Group(id: "Select", rows: [
            ("Rectangle Select", "⇧⌘M"), ("Lasso Select", "⇧⌘L"), ("Magic Wand", "⇧⌘W"), ("Pointer (no tool)", "⇧⌘P"),
            ("Select All", "⌘A"), ("Deselect", "⇧⌘A"), ("Invert Selection", "⌘I"), ("Delete selected pixels", "⌫"),
            ("Add to selection", "Shift-click or drag"), ("Subtract from selection", "Option-click or drag"),
        ]),
        Group(id: "Adjustments", rows: [
            ("Black and White", "⇧⌘G"), ("Invert Colors", "⇧⌘I"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Keyboard Shortcuts").font(.title2.bold())
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.id).font(.headline).foregroundStyle(Brand.violet)
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(row.0)
                                Spacer()
                                Text(row.1).monospaced().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text("Hover over any button for a short description.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 400, height: 560)
    }
}
