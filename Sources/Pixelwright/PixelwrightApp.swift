import AppKit
import SwiftUI

@main
struct PixelwrightApp: App {
    @StateObject private var model = AppModel()

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
                .onOpenURL { model.open($0) }
        }
        .defaultSize(width: 960, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openWithPanel() }
                    .keyboardShortcut("o")
                Button("Save As…") { model.saveWithPanel() }
                    .keyboardShortcut("s")
                    .disabled(!model.canEdit)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo)
                Button("Redo") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
            CommandMenu("Select") {
                Button("Magic Wand") { model.tool = model.tool == .magicWand ? .none : .magicWand }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(!model.hasImage)
                Divider()
                Button("Select All") { model.selectAll() }
                    .keyboardShortcut("a")
                    .disabled(!model.canEdit)
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
            CommandMenu("Image") {
                Button("Resize…") { model.showingResize = true }
                    .keyboardShortcut("r")
                    .disabled(!model.canEdit)
                Button("Canvas Size…") { model.showingCanvasSize = true }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!model.canEdit)
                Divider()
                Button("Remove Background") { model.removeBackground() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(!model.canEdit)
            }
        }
    }
}
