import AppKit
import SwiftUI

/// Placeholder window for the not-yet-built Recording feature, reached from the menubar menu.
///
/// Same AppKit-window pattern as `VocabularyWindow` (SwiftUI sheets/popovers misbehave inside
/// `MenuBarExtra(.window)`). Intentionally does nothing else yet — it exists so the menu entry
/// leads somewhere honest instead of being inert.
final class RecordingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    // Keep alive until the window closes — all access on the main thread.
    private static var active: [RecordingWindow] = []

    static func show() {
        DispatchQueue.main.async {
            // Re-front an already-open window rather than stacking duplicates.
            if let existing = active.first, let w = existing.window {
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            let owner = RecordingWindow()
            active.append(owner)

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 312, height: 152),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Record Voice & Text"
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = owner
            w.contentView = NSHostingView(rootView: RecordingPlaceholderView())
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            owner.window = w
        }
    }

    func windowWillClose(_ notification: Notification) {
        RecordingWindow.active.removeAll { $0 === self }
    }
}

private struct RecordingPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "record.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(OWColor.accentDeep)

            Text("In development")
                .font(OWFont.title(17))
                .foregroundColor(OWColor.ink)

            Text("Recording your voice and the text it produces isn't built yet. It'll show up here in a future release.")
                .font(OWFont.caption())
                .foregroundColor(OWColor.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        // Explicit, not `maxHeight: .infinity` — NSHostingView propagates the view's intrinsic
        // size to the window, so an unbounded height made the window grow to ~855pt.
        .frame(width: 312, height: 152)
        .background(OWColor.page)
    }
}
