import AppKit
import SwiftUI
import CoreText
import OpenWhispererKit

// MARK: - Color helpers (warm "Open Whisperer" palette from openwhisperer.com)
//
// Tokens are appearance-aware: a light value (the site's cream/gold) and a warm-dark
// value so the menubar popover never shows a bright cream panel against a dark menu bar.

extension NSColor {
    /// Build an opaque sRGB color from a 0xRRGGBB literal.
    fileprivate convenience init(owHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// A dynamic color that resolves to `light` in Aqua and `dark` in Dark Aqua.
    static func ow(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(owHex: isDark ? dark : light)
        }
    }
}

extension Color {
    /// Wrap a dynamic NSColor as a SwiftUI Color (keeps light/dark adaptation).
    static func ow(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: .ow(light, dark))
    }
}

// MARK: - Design tokens

// Warm "Open Whisperer" palette (openwhisperer.com). Tokens are light/dark dynamic —
// via the `Color.ow(light, dark)` helper above. Used by the branded menubar popover
// (the tabbed Settings window) and the transcription overlay.
/// Live colour tokens for the selected theme.
///
/// Every token is a computed `var`, not a `let`: the palette changes at runtime when the user
/// picks a theme, and a stored constant would freeze the launch-time appearance. `ThemeManager`
/// publishes the change so SwiftUI re-renders and re-reads these.
enum OWColor {
    private static var light: OWPalette { ThemeManager.activePalettes.light }
    private static var dark: OWPalette { ThemeManager.activePalettes.dark }

    private static func token(_ keyPath: KeyPath<OWPalette, UInt32>) -> Color {
        .ow(light[keyPath: keyPath], dark[keyPath: keyPath])
    }

    // Surfaces
    static var page: Color { token(\.page) }
    static var surface: Color { token(\.surface) }
    static var cardBackground: Color { surface }              // legacy alias (OWCard)
    // Lines
    static var line: Color { token(\.line) }
    static var divider: Color { line }                        // legacy alias
    // Text ramp
    static var ink: Color { token(\.ink) }
    static var inkSoft: Color { token(\.inkSoft) }
    static var inkFaint: Color { token(\.inkFaint) }
    static var muted: Color { inkSoft }                       // legacy alias
    // Accent
    static var accent: Color { token(\.accent) }
    static var accentDeep: Color { token(\.accentDeep) }
    static var onAccent: Color { token(\.onAccent) }
    static var success: Color { accentDeep }
    // Fills
    static var pillFill: Color { token(\.pillFill) }
    static var pickerBg: Color { token(\.pickerBg) }
    static var pickerBorder: Color { token(\.pickerBorder) }
    static var checkboxBorder: Color { token(\.checkboxBorder) }
    static var pillBackground: Color { pillFill }             // legacy alias
    // Status semantics — warm equivalents of system red/amber/green so dots + badges don't
    // clash with the palette (the system colors are especially jarring in dark mode).
    static var recording: Color { token(\.recording) }
    static var warn: Color { token(\.warn) }
    static var live: Color { token(\.live) }
    static var danger: Color { recording }                    // alias for error states
}

// MARK: - Bundled font registration
//
// Registered as early as possible (App.init) so the custom faces are available before
// SwiftUI composes the first layout pass — otherwise the system fallback gets cached.

// Both call sites (App.init, applicationDidFinishLaunching) run on the main thread, so this
// is never contended; `nonisolated(unsafe)` documents that and silences strict-concurrency.
private nonisolated(unsafe) var owFontsRegistered = false

func registerBundledFonts() {
    guard !owFontsRegistered else { return }
    owFontsRegistered = true
    for resource in ["Outfit-VariableFont_wght", "Fraunces"] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf") else {
            NSLog("OpenWhisperer: bundled font missing: \(resource).ttf")
            continue
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            NSLog("OpenWhisperer: font registration failed for \(resource): \(String(describing: error?.takeRetainedValue()))")
        }
    }
}


/// Tints the popover's window chrome to the warm cream/dark background so the branded
/// MenuBarExtra(.window) has no default material edge. Restored 2026-07-19 with the popover UI.
struct OWWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(to: nsView.window) }
    }

    /// Solid, deliberately not glass. Translucency was tried on 2026-07-31 and reverted:
    /// `NSVisualEffectView` needs `isOpaque = false` plus a clear background to blur what is
    /// behind it, which also removes the window's visible edge and its drag region, and leaves
    /// the titlebar showing raw desktop because the effect view covers only the content area.
    /// Doing it properly needs `.fullSizeContentView` and a manual titlebar inset — and the
    /// menubar dropdown is a system-drawn `NSMenu` that could never be matched anyway.
    private static func apply(to window: NSWindow?) {
        guard let window else { return }
        let palettes = ThemeManager.activePalettes
        window.backgroundColor = .ow(palettes.light.page, palettes.dark.page)
        // Also on creation, so a window opened *after* the theme was chosen matches it.
        window.appearance = ThemeManager.shared.windowAppearance
    }
}


// MARK: - Brand fonts

enum OWFont {
    /// Brand serif for the wordmark + titled headers. The bundled cut is a single SemiBold static
    /// face (family "Fraunces SemiBold"), so the weight is intrinsic — no `.weight()` needed.
    static func title(_ size: CGFloat = 15) -> Font {
        .custom("Fraunces SemiBold", size: size)
    }
    static func serif(_ size: CGFloat = 15) -> Font {
        .custom("Fraunces SemiBold", size: size)
    }
    static func sectionLabel(_ size: CGFloat = 11) -> Font {
        .custom("Outfit", size: size).weight(.semibold)
    }
    static func body(_ size: CGFloat = 13) -> Font {
        .custom("Outfit", size: size)
    }
    static func caption(_ size: CGFloat = 10) -> Font {
        .custom("Outfit", size: size)
    }
    static func mono(_ size: CGFloat = 11) -> Font {
        .custom("Outfit", size: size).monospaced()
    }
}
