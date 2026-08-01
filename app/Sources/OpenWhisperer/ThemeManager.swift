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

    /// Push the palette into the static `OWColor` reads, and tell AppKit which appearance the
    /// app's own windows should use. Without the appearance override a fixed dark theme would
    /// still draw system chrome (titlebar, menus, focus rings) in light mode, and vice versa.
    private func apply() {
        Self.activePalettes = theme.palettes
        switch theme {
        case .cream:
            NSApp?.appearance = nil                 // follow the system, as the app always has
        case .dark:
            NSApp?.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp?.appearance = NSAppearance(named: .aqua)
        }
        // Windows cache their background colour, so repaint the ones we own.
        for window in NSApp?.windows ?? [] {
            window.backgroundColor = .ow(theme.palettes.light.page, theme.palettes.dark.page)
        }
        // The overlay's faceplate is a CALayer colour, which SwiftUI never re-evaluates.
        if isInitialised { TranscriptionOverlay.shared.refreshTheme() }
    }

    private func persist() {
        try? theme.rawValue.write(to: Paths.uiTheme, atomically: true, encoding: .utf8)
    }
}
