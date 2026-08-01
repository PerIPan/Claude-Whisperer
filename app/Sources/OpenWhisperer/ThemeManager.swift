import AppKit
import Combine
import OpenWhispererKit
import SwiftUI

/// Owns the selected appearance and republishes it so SwiftUI re-renders when it changes.
///
/// `OWColor`'s tokens are computed and read `activePalettes`, which is a plain static so the
/// colour lookups stay cheap and callable from anywhere (including AppKit code that has no
/// environment). `@Published var theme` is what actually drives redraws; the static is kept in
/// step by `apply`, never written independently.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    /// Read by `OWColor` on every token access. Main-thread only, like the rest of the UI.
    nonisolated(unsafe) private(set) static var activePalettes: (light: OWPalette, dark: OWPalette)
        = OWTheme.default.palettes

    @Published var theme: OWTheme {
        didSet {
            guard theme != oldValue else { return }
            apply()
            persist()
        }
    }

    /// False until `init` returns, so the first `apply()` doesn't reach for
    /// `TranscriptionOverlay.shared` and construct the overlay singleton during startup. The
    /// overlay reads the palette when it builds its window, so it needs no refresh then.
    private var isInitialised = false

    private init() {
        let stored = try? String(contentsOf: Paths.uiTheme, encoding: .utf8)
        theme = OWTheme.parse(stored)
        apply()
        isInitialised = true
    }

    /// The AppKit appearance a theme's own windows should draw with, or `nil` to follow the
    /// system. A fixed theme needs this so its titlebar, focus rings and scrollbars match the
    /// palette rather than whatever macOS is set to.
    var windowAppearance: NSAppearance? {
        switch theme {
        case .cream: return nil                                 // follow the system, as always
        case .dark: return NSAppearance(named: .darkAqua)
        default: return NSAppearance(named: .aqua)
        }
    }

    /// Push the palette into the static `OWColor` reads and restyle the windows we own.
    ///
    /// Deliberately **not** `NSApp.appearance`. Setting that styles every window the process
    /// has, including the menubar status item — which must keep following the system menu bar.
    /// Forcing it light against a dark menu bar drew a white block behind the icon.
    private func apply() {
        Self.activePalettes = theme.palettes
        let background = NSColor.ow(theme.palettes.light.page, theme.palettes.dark.page)
        for window in NSApp?.windows ?? [] where Self.isOwnWindow(window) {
            window.appearance = windowAppearance
            window.backgroundColor = background
        }
        // The overlay's faceplate is a CALayer colour, which SwiftUI never re-evaluates.
        if isInitialised { TranscriptionOverlay.shared.refreshTheme() }
    }

    /// Whether a window is one of ours to restyle. Excludes the status-item window and the
    /// menubar popover, which belong to the menu bar's appearance, not the app's theme.
    private static func isOwnWindow(_ window: NSWindow) -> Bool {
        let name = String(describing: type(of: window))
        return !name.contains("StatusBar") && !name.contains("MenuBarExtra")
            && !name.contains("NSPopover") && !name.contains("Popover")
    }

    private func persist() {
        try? theme.rawValue.write(to: Paths.uiTheme, atomically: true, encoding: .utf8)
    }
}
