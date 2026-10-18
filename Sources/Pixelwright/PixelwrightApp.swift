import AppKit
import SwiftUI

@main
struct PixelwrightApp: App {
    @StateObject private var model = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        // Lets `swift run` show a proper windowed app with a menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        Window("Pixelwright", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 560)
        }
        .defaultSize(width: 960, height: 700)

        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsView().tint(Brand.accent)
        }
        .windowResizability(.contentSize)

        Window("About \(Brand.name)", id: "about") {
            AboutView().tint(Brand.accent)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }
                    .keyboardShortcut("/", modifiers: .command)
                Divider()
                Link("Pixelwright on GitHub", destination: Brand.repositoryURL)
                Link("Report a Problem", destination: Brand.repositoryURL.appendingPathComponent("issues"))
            }
            CommandGroup(replacing: .appInfo) {
                Button("About \(Brand.name)") { openWindow(id: "about") }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openWithPanel() }
                    .keyboardShortcut("o")
                Button("Save a Copy…") { model.saveCopy() }
                    .keyboardShortcut("s")
                    .disabled(!model.canEdit)
                Button("Export…") { model.showingExport = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!model.canEdit)
                Divider()
                Button("Batch Resize…") { model.showingBatch = true }
                    .keyboardShortcut("b", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .undoRedo) {
                Button(model.undoMenuTitle) { model.undoCommand() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo && !model.isSheetOpen)
                Button(model.redoMenuTitle) { model.redoCommand() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo && !model.isSheetOpen)
            }
            CommandMenu("Select") {
                Button("Rectangle Select") { model.tool = .rectangleSelect }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(!model.hasImage)
                Button("Lasso Select") { model.tool = .lasso }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(!model.hasImage)
                Button("Magic Wand") { model.tool = .magicWand }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(!model.hasImage)
                Button("Pointer") { model.tool = .none }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(!model.hasImage)
                Divider()
                Button("Select All") { model.selectAllCommand() }
                    .keyboardShortcut("a")
                    .disabled(!model.canUseEditCommand)
                Button("Deselect") { model.deselect() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!model.hasSelection)
                Button("Invert Selection") { model.invertSelection() }
                    .keyboardShortcut("i")
                    .disabled(!model.canEdit)
                Divider()
                Button("Expand Selection by 1 px") { model.growSelection(by: 1) }
                    .disabled(!model.hasSelection)
                Button("Contract Selection by 1 px") { model.growSelection(by: -1) }
                    .disabled(!model.hasSelection)
                Divider()
                Button("Delete Selection") { model.deleteSelection() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(!model.hasSelection || !model.canEdit)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { model.cutCommand() }
                    .keyboardShortcut("x")
                    .disabled(!model.canUseEditCommand)
                Button("Copy") { model.copyCommand() }
                    .keyboardShortcut("c")
                    .disabled(!model.canUseEditCommand)
                Button("Paste") { model.pasteCommand() }
                    .keyboardShortcut("v")
                    .disabled(model.isBusy)
            }
            CommandMenu("Adjustments") {
                Button("Brightness / Contrast…") { model.effectSheet = .brightnessContrast }
                    .disabled(!model.canEdit)
                Button("Hue / Saturation…") { model.effectSheet = .hueSaturation }
                    .disabled(!model.canEdit)
                Divider()
                Button("Black and White") { model.applyEffect(.blackAndWhite) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(!model.canEdit)
                Button("Sepia") { model.applyEffect(.sepia) }
                    .disabled(!model.canEdit)
                Button("Invert Colors") { model.applyEffect(.invertColors) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(!model.canEdit)
            }
            CommandMenu("Effects") {
                Button("Blur…") { model.effectSheet = .blur }
                    .disabled(!model.canEdit)
                Button("Sharpen…") { model.effectSheet = .sharpen }
                    .disabled(!model.canEdit)
                Button("Pixelate…") { model.effectSheet = .pixelate }
                    .disabled(!model.canEdit)
            }
            CommandMenu("Image") {
                Button("Resize…") { model.showingResize = true }
                    .keyboardShortcut("r")
                    .disabled(!model.canEdit)
                Button("Canvas Size…") { model.showingCanvasSize = true }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!model.canEdit)
                Divider()
                Button("Crop to Selection") { model.cropToSelection() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                    .disabled(!model.hasSelection || !model.canEdit)
                Button("Auto-Crop Transparent Edges") { model.autoCrop() }
                    .disabled(!model.canEdit)
                Divider()
                Button("Rotate 90° Clockwise") { model.rotate(.clockwise90) }
                    .keyboardShortcut("]")
                    .disabled(!model.canEdit)
                Button("Rotate 90° Counterclockwise") { model.rotate(.counterclockwise90) }
                    .keyboardShortcut("[")
                    .disabled(!model.canEdit)
                Button("Rotate 180°") { model.rotate(.half) }
                    .disabled(!model.canEdit)
                Button("Flip Horizontal") { model.flipHorizontally() }
                    .disabled(!model.canEdit)
                Button("Flip Vertical") { model.flipVertically() }
                    .disabled(!model.canEdit)
                Divider()
                Button("Remove Background") { model.removeBackground() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(!model.canEdit)
            }
        }
    }
}
