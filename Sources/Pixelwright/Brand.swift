import SwiftUI

/// Pixelwright's identity: name, tagline, colors and the precision "P" mark.
/// The same artwork is generated for the app icon by `scripts/make-icon.swift`; keep them in sync.
enum Brand {
    static let name = "Pixelwright"
    static let tagline = "Craft your pixels."
    static let descriptor = "The private, focused image editor for Mac."
    static let repositoryURL = URL(string: "https://github.com/architpoddar/Pixelwright")!
    static let licenseName = "MIT License"

    // Base Neutrals
    static let obsidian = Color(red: 0x0B / 255, green: 0x0E / 255, blue: 0x14 / 255)
    static let darkSlate = Color(red: 0x1E / 255, green: 0x26 / 255, blue: 0x38 / 255)
    static let titanium = Color(red: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255)
    static let titaniumShade = Color(red: 0xE2 / 255, green: 0xE8 / 255, blue: 0xF0 / 255)

    // Confident Accents
    static let cobalt = Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
    static let cobaltDeep = Color(red: 0x1D / 255, green: 0x4E / 255, blue: 0xD8 / 255)
    static let selection = Color(red: 0x0E / 255, green: 0xA5 / 255, blue: 0xE9 / 255)

    // Backward-compatible color aliases
    static let indigo = darkSlate
    static let violet = cobalt
    static let coral = selection
    static let spark = cobalt

    /// The signature dark slate machined gradient.
    static let gradient = LinearGradient(
        stops: [.init(color: darkSlate, location: 0), .init(color: obsidian, location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// The color used for buttons, active controls and primary highlights across the app.
    static let accent = cobalt

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        return "Version \(version)"
    }
}

/// The sculptural ribbon P glyph.
struct RibbonPGlyph: View {
    var size: CGFloat = 36

    var body: some View {
        let scale = size / 60.0
        Canvas { context, canvasSize in
            let originX = (canvasSize.width - 60.0 * scale) / 2
            let originY = (canvasSize.height - 74.0 * scale) / 2

            var path = Path()
            path.move(to: CGPoint(x: (34 - 26) * scale, y: (16 - 16) * scale))
            path.addCurve(
                to: CGPoint(x: (76 - 26) * scale, y: (26 - 16) * scale),
                control1: CGPoint(x: (48 - 26) * scale, y: (16 - 16) * scale),
                control2: CGPoint(x: (66 - 26) * scale, y: (16 - 16) * scale))
            path.addCurve(
                to: CGPoint(x: (76 - 26) * scale, y: (58 - 16) * scale),
                control1: CGPoint(x: (86 - 26) * scale, y: (36 - 16) * scale),
                control2: CGPoint(x: (86 - 26) * scale, y: (48 - 16) * scale))
            path.addCurve(
                to: CGPoint(x: (42 - 26) * scale, y: (66 - 16) * scale),
                control1: CGPoint(x: (66 - 26) * scale, y: (66 - 16) * scale),
                control2: CGPoint(x: (52 - 26) * scale, y: (66 - 16) * scale))
            path.addLine(to: CGPoint(x: (42 - 26) * scale, y: (82 - 16) * scale))
            path.addCurve(
                to: CGPoint(x: (34 - 26) * scale, y: (90 - 16) * scale),
                control1: CGPoint(x: (42 - 26) * scale, y: (86.4 - 16) * scale),
                control2: CGPoint(x: (38.4 - 26) * scale, y: (90 - 16) * scale))
            path.addCurve(
                to: CGPoint(x: (26 - 26) * scale, y: (82 - 16) * scale),
                control1: CGPoint(x: (29.6 - 26) * scale, y: (90 - 16) * scale),
                control2: CGPoint(x: (26 - 26) * scale, y: (86.4 - 16) * scale))
            path.addLine(to: CGPoint(x: (26 - 26) * scale, y: (24 - 16) * scale))
            path.addCurve(
                to: CGPoint(x: (34 - 26) * scale, y: (16 - 16) * scale),
                control1: CGPoint(x: (26 - 26) * scale, y: (19.6 - 16) * scale),
                control2: CGPoint(x: (29.6 - 26) * scale, y: (16 - 16) * scale))
            path.closeSubpath()

            // Inner counter loop
            var inner = Path()
            inner.move(to: CGPoint(x: (42 - 26) * scale, y: (30 - 16) * scale))
            inner.addLine(to: CGPoint(x: (42 - 26) * scale, y: (52 - 16) * scale))
            inner.addCurve(
                to: CGPoint(x: (66 - 26) * scale, y: (46 - 16) * scale),
                control1: CGPoint(x: (48 - 26) * scale, y: (52 - 16) * scale),
                control2: CGPoint(x: (60 - 26) * scale, y: (52 - 16) * scale))
            inner.addCurve(
                to: CGPoint(x: (66 - 26) * scale, y: (26 - 16) * scale),
                control1: CGPoint(x: (72 - 26) * scale, y: (40 - 16) * scale),
                control2: CGPoint(x: (72 - 26) * scale, y: (32 - 16) * scale))
            inner.addCurve(
                to: CGPoint(x: (42 - 26) * scale, y: (30 - 16) * scale),
                control1: CGPoint(x: (60 - 26) * scale, y: (20 - 16) * scale),
                control2: CGPoint(x: (48 - 26) * scale, y: (20 - 16) * scale))
            inner.closeSubpath()

            context.translateBy(x: originX, y: originY)
            var combined = Path()
            combined.addPath(path)
            combined.addPath(inner)

            context.fill(
                combined,
                with: .linearGradient(
                    Gradient(colors: [Brand.titanium, Brand.titaniumShade]),
                    startPoint: CGPoint(x: 15 * scale, y: 0),
                    endPoint: CGPoint(x: 45 * scale, y: 74 * scale)
                ), style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size * (74.0 / 60.0))
    }
}

/// The app icon's tile: dark machined squircle with the sculptural ribbon P. Scales to any size.
struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Brand.gradient)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
            RibbonPGlyph(size: size * 0.52)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.28), radius: size * 0.05, y: size * 0.025)
    }
}

/// Confident, crafted wordmark.
struct Wordmark: View {
    var size: CGFloat = 28

    var body: some View {
        Text(Brand.name)
            .font(.system(size: size, weight: .semibold, design: .default))
            .tracking(-size * 0.025)
            .foregroundColor(.primary)
            .accessibilityLabel(Brand.name)
    }
}

/// A compact brand chip for the toolbar: mark and name.
struct BrandChip: View {
    var body: some View {
        HStack(spacing: 7) {
            BrandMark(size: 20)
            Wordmark(size: 14)
        }
        .padding(.horizontal, 4)
        .help("\(Brand.name): \(Brand.tagline)")
    }
}

/// Shown when no image is open.
struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            BrandMark(size: 112)
            Wordmark(size: 38)
            Text(Brand.tagline)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
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
            .padding(.top, 8)

            Text("or drop an image anywhere in this window")
                .font(.callout)
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Label("100% on-device. No servers, no accounts, and no uploads.", systemImage: "network.slash")
                Label("Your original files are never changed. Saving always makes a copy.", systemImage: "lock.shield")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 14)
        }
        .padding(40)
    }
}

/// The About window.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            BrandMark(size: 96)
            Wordmark(size: 30)
            Text(Brand.tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Brand.versionString)
                .font(.callout)
                .foregroundStyle(.tertiary)
            Divider().padding(.vertical, 4)
            Text("The private, focused image editor for Mac.\nYour images never leave your computer,\nand your original files are never changed.")
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
                        Text(group.id).font(.headline).foregroundStyle(Brand.accent)
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
