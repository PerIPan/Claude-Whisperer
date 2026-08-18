import AppKit
import SwiftUI

/// Hosts `FirstRunView` in a standalone window.
///
/// Same pattern as `SettingsWindow` (plain `NSWindow`, not a SwiftUI `Settings` scene) for
/// the same reasons: an `LSUIElement` app has activation quirks presenting the system
/// scene, and its toolbar strip can't be recolored to match the theme.
///
/// Not an `NSAlert` or a sheet: there is no parent window to attach to at launch, and a
/// modal would contradict the "nothing blocks" rule — you can leave this open and go use
/// the app, or close it and never see it again.
final class FirstRunWindow: NSObject, NSWindowDelegate {
    private static var shared: FirstRunWindow?

    private var window: NSWindow?
    private var selection: FirstRunSelection?
    /// Marks setup complete when the window goes away, however it goes away — Done, Skip,
    /// or the red close button. Without this, closing by the title bar would re-show the
    /// sheet on every launch.
    private var onClose: (() -> Void)?

    static func show(appDelegate: AppDelegate, onClose: @escaping () -> Void) {
        DispatchQueue.main.async {
            if let existing = shared, let w = existing.window {
                // Adopt the newer closure rather than keeping the one from the first call.
                // Unreachable while the only caller was first launch; the menubar's "Setup…"
                // makes a second call real, and silently dropping its `onClose` would mean
                // that invocation never completes.
                existing.onClose = onClose
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let owner = FirstRunWindow()
            shared = owner
            owner.onClose = onClose

            let selection = FirstRunSelection()
            owner.selection = selection

            let root = FirstRunView()
                .environmentObject(selection)
                .environmentObject(appDelegate.serverManager)
                .environmentObject(appDelegate.dictationManager)
                .environmentObject(appDelegate.accessibilityManager)

            let controller = NSHostingController(rootView: AnyView(root))
            let w = NSWindow(contentViewController: controller)
            w.title = "Welcome to Open Whisperer"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = owner
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            owner.window = w
        }
    }

    /// Close from inside the view (Done / Skip setup). Routes through `performClose` so it
    /// takes the same path as the title-bar button and `windowWillClose` runs either way.
    static func finish() {
        DispatchQueue.main.async {
            shared?.window?.performClose(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
        FirstRunWindow.shared = nil
        window = nil
        selection = nil
    }
}
