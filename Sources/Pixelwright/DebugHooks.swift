import AppKit

/// Developer hooks, active only when environment variables are set. They let you launch the app,
/// get it into a known state, and save a picture of its window without screen-recording permission.
///
///     PIXELWRIGHT_DEBUG_OPEN=/path/to/image.png    open this file
///     PIXELWRIGHT_DEBUG_TOOL=wand                   rect, lasso or wand
///     PIXELWRIGHT_DEBUG_SELECT_ALL=1                select everything
///     PIXELWRIGHT_DEBUG_EDIT=1                      make an edit (invert), to show the "edited" state
///     PIXELWRIGHT_DEBUG_SIZE=700x600                window content size
///     PIXELWRIGHT_SNAPSHOT=/tmp/window.png          where to write a picture of the window, then quit
///                                                   (leave it out to keep the app open in that state)
///
///     (launched with: open -n -a build/Pixelwright.app --env NAME=value ...)
///
/// Launch it through `open` with `--env NAME=value` for each setting; running the binary directly
/// doesn't create a window. The app quits after writing the snapshot. Tools: rect, lasso, wand.
/// The toolbar buttons in the snapshot appear as plain white shapes; that is how the snapshot
/// method draws native toolbar items, not a bug in the app.
@MainActor
enum DebugHooks {
    private static var started = false

    static func start(window: NSWindow, model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard !started, env.keys.contains(where: { $0.hasPrefix("PIXELWRIGHT_DEBUG_") || $0 == "PIXELWRIGHT_SNAPSHOT" }) else { return }
        started = true
        let snapshotPath = env["PIXELWRIGHT_SNAPSHOT"]

        if let path = env["PIXELWRIGHT_DEBUG_OPEN"] { model.open(URL(fileURLWithPath: path)) }

        if let size = env["PIXELWRIGHT_DEBUG_SIZE"] {
            let parts = size.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { window.setContentSize(NSSize(width: parts[0], height: parts[1])) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            switch env["PIXELWRIGHT_DEBUG_TOOL"] {
            case "rect": model.tool = .rectangleSelect
            case "lasso": model.tool = .lasso
            case "wand":
                model.tool = .magicWand
                if env["PIXELWRIGHT_DEBUG_WAND_CLICK"] != nil {
                    model.wandClick(x: 480, y: 150, combine: .replace)
                }
            default: break
            }
            if env["PIXELWRIGHT_DEBUG_SELECT_ALL"] != nil { model.selectAll() }
            if env["PIXELWRIGHT_DEBUG_EDIT"] != nil { model.applyEffect(.invertColors) }

            // Without PIXELWRIGHT_SNAPSHOT the app just stays open in that state.
            guard let snapshotPath else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                snapshot(window, to: snapshotPath)
                NSApp.terminate(nil)
            }
        }
    }

    private static func snapshot(_ window: NSWindow, to path: String) {
        typealias CGWindowListCreateImageFunc = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
           let sym = dlsym(handle, "CGWindowListCreateImage") {
            let fn = unsafeBitCast(sym, to: CGWindowListCreateImageFunc.self)
            // kCGWindowListOptionIncludingWindow = 1, kCGWindowImageBoundsIgnoreFraming = 1
            if let unmanaged = fn(.null, 1, UInt32(window.windowNumber), 1) {
                let cgImage = unmanaged.takeRetainedValue()
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                    return
                }
            }
        }

        guard let content = window.contentView else { return }
        let view = content.superview ?? content  // the frame view includes the title bar and toolbar
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
