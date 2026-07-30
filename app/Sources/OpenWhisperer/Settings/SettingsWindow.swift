import AppKit
import SwiftUI

/// Owns which tab is showing. Lives outside the SwiftUI view so re-opening an
/// already-open window can still switch tabs (a `@State` in the view could not).
final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab
    init(tab: SettingsTab) { self.tab = tab }
}

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
    private var selection: SettingsSelection?

    /// Open (or re-front) the Settings window on `tab`.
    static func show(tab: SettingsTab, appDelegate: AppDelegate) {
        DispatchQueue.main.async {
            // Already open: re-front AND honor the requested tab (an early return that
            // ignored `tab` would silently break "a missing grant lands you on General").
            if let existing = shared, let w = existing.window {
                existing.selection?.tab = tab
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let owner = SettingsWindow()
            shared = owner

            let selection = SettingsSelection(tab: tab)
            owner.selection = selection

            let root = SettingsView()
                .environmentObject(selection)
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

            owner.window = w
        }
    }

    /// Land on General when something needs attention (a missing grant lives there),
    /// otherwise the first tab — Dictation.
    static func preferredTab(for appDelegate: AppDelegate) -> SettingsTab {
        let needsGrant = !appDelegate.accessibilityManager.isGranted
            || !appDelegate.dictationManager.recorder.micPermission
        return needsGrant ? .general : .dictation
    }

    func windowWillClose(_ notification: Notification) {
        SettingsWindow.shared = nil
        window = nil
        selection = nil
    }
}
