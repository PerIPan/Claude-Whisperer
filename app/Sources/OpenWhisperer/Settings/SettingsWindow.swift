import AppKit
import SwiftUI

/// Hosts `SettingsView` in a standalone titled window.
///
/// Deliberately NOT a SwiftUI `Settings` scene: that scene's `TabView` draws a system
/// toolbar strip we can't recolor, and presenting it from an `LSUIElement` app has
/// known activation quirks. A plain `NSWindow` (the pattern already proven by
/// `VocabularyWindow` / `InstructionWindow`) gives full control of the chrome.
final class SettingsWindow: NSObject, NSWindowDelegate {
    /// The single live instance (the window is a singleton — reopening re-fronts it).
    private static var shared: SettingsWindow?

    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?

    /// Open (or re-front) the Settings window.
    /// - Parameter tab: which tab to select when the window is first created.
    static func show(tab: SettingsTab = .general, appDelegate: AppDelegate) {
        DispatchQueue.main.async {
            if let existing = shared, let w = existing.window {
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let owner = SettingsWindow()
            shared = owner

            let root = SettingsView(initialTab: tab)
                .environmentObject(appDelegate.serverManager)
                .environmentObject(appDelegate.setupManager)
                .environmentObject(appDelegate.dictationManager)
                .environmentObject(appDelegate.accessibilityManager)

            // NSHostingController propagates SwiftUI's intrinsic size as the window's
            // content size, so switching tabs resizes the window to fit each tab.
            let controller = NSHostingController(rootView: AnyView(root))
            let w = NSWindow(contentViewController: controller)
            w.title = "Open Whisperer Settings"
            w.styleMask = [.titled, .closable]   // fixed size: no .resizable
            w.isReleasedWhenClosed = false
            w.delegate = owner
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            owner.hosting = controller
            owner.window = w
        }
    }

    func windowWillClose(_ notification: Notification) {
        SettingsWindow.shared = nil
        window = nil
        hosting = nil
    }
}
