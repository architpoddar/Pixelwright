import AppKit
import SwiftUI

/// Hooks the app's window up to the standard Mac document behavior: the dot in the close button
/// when there are unsaved changes, the file icon in the title bar, and a question before an
/// unsaved image would be thrown away.
struct WindowAccessor: NSViewRepresentable {
    let model: AppModel
    let isEdited: Bool
    let fileURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = WindowTrackingView()
        let coordinator = context.coordinator
        let model = self.model
        view.onWindow = { window in coordinator.attach(to: window, model: model) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        context.coordinator.attach(to: window, model: model)
        window.isDocumentEdited = isEdited
        window.representedURL = fileURL
    }

    /// Reports the window as soon as the view is placed in one.
    final class WindowTrackingView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { [onWindow] in onWindow?(window) } }
        }
    }

    @MainActor
    final class Coordinator {
        private var closeGuard: CloseGuard?

        func attach(to window: NSWindow?, model: AppModel) {
            guard let window, closeGuard == nil || window.delegate !== closeGuard else { return }
            let guardObject = CloseGuard(model: model, original: window.delegate)
            closeGuard = guardObject  // the window only holds its delegate weakly
            window.delegate = guardObject
            DebugHooks.start(window: window, model: model)
        }
    }
}

/// Stands in as the window's delegate to ask before closing an edited image, and passes everything
/// else to the delegate SwiftUI installed.
@MainActor
final class CloseGuard: NSObject, NSWindowDelegate {
    private let model: AppModel
    private weak var original: NSWindowDelegate?

    init(model: AppModel, original: NSWindowDelegate?) {
        self.model = model
        self.original = original
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if let original, original.responds(to: selector) { return original }
        return super.forwardingTarget(for: selector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.confirmDiscardIfNeeded(action: "close this window") else { return false }
        model.closeImage()
        return original?.windowShouldClose?(sender) ?? true
    }
}

/// Handles files opened from Finder or `open`, and asks about unsaved changes when quitting.
///
/// File opens are handled here rather than with `.onOpenURL`: once an app delegate is installed,
/// SwiftUI stops delivering URLs to `.onOpenURL` while the app is already running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated { AppModel.shared.open(url) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            AppModel.shared.confirmDiscardIfNeeded(action: "quit") ? .terminateNow : .terminateCancel
        }
    }
}
