import Foundation

/// One appearance's colour tokens, as 0xRRGGBB literals.
///
/// Deliberately raw integers rather than SwiftUI `Color`s so the whole theme table stays in
/// dependency-free `OpenWhispererKit` and unit-tests under Command Line Tools. The app maps
/// these to `Color` in `OWColor`.
public struct OWPalette: Sendable, Equatable {
    // Surfaces
    public let page: UInt32
    public let surface: UInt32
    public let line: UInt32
    // Text ramp
    public let ink: UInt32
    public let inkSoft: UInt32
    public let inkFaint: UInt32
    // Accent
    public let accent: UInt32
    public let accentDeep: UInt32
    public let onAccent: UInt32
    // Fills
    public let pillFill: UInt32
    public let pickerBg: UInt32
    public let pickerBorder: UInt32
    public let checkboxBorder: UInt32
    // Status semantics
    public let recording: UInt32
    public let warn: UInt32
    public let live: UInt32

    public init(
        page: UInt32, surface: UInt32, line: UInt32,
        ink: UInt32, inkSoft: UInt32, inkFaint: UInt32,
        accent: UInt32, accentDeep: UInt32, onAccent: UInt32,
        pillFill: UInt32, pickerBg: UInt32, pickerBorder: UInt32, checkboxBorder: UInt32,
        recording: UInt32, warn: UInt32, live: UInt32
    ) {
        self.page = page; self.surface = surface; self.line = line
        self.ink = ink; self.inkSoft = inkSoft; self.inkFaint = inkFaint
        self.accent = accent; self.accentDeep = accentDeep; self.onAccent = onAccent
        self.pillFill = pillFill; self.pickerBg = pickerBg
        self.pickerBorder = pickerBorder; self.checkboxBorder = checkboxBorder
        self.recording = recording; self.warn = warn; self.live = live
    }
}

/// The app's selectable appearances.
///
/// **Cream** is the original Open Whisperer identity and the default; it is the only theme that
/// follows the system's light/dark appearance, because that is how the app has always behaved.
/// The other five are ports of the Authé design system's palettes (`apps/authe-app/app/globals.css`
/// — `:root`, `.dark`, `.pastel`, `.champ`, `.sky-champ`), whose OKLCH values were converted to
/// sRGB. A fixed theme deliberately does *not* follow the system appearance: picking "Dark" means
/// dark, not "dark unless macOS says otherwise".
public enum OWTheme: String, CaseIterable, Sendable, Equatable {
    case cream
    case light
    case dark
    case pastel
    case champagne
    case sky

    public static let `default`: OWTheme = .cream

    public var label: String {
        switch self {
        case .cream: return "Cream"
        case .light: return "Light"
        case .dark: return "Dark"
        case .pastel: return "Pastel"
        case .champagne: return "Champagne"
        case .sky: return "Sky"
        }
    }

    /// A one-line description of the palette, shown under the picker.
    ///
    /// Every fixed theme states that it stays put. Saying so only on Cream would leave the rule
    /// to be inferred from the *absence* of a phrase on the other five, which nobody does — and
    /// the app's whole pre-2.0 behaviour was "always matches your Mac", so opting out of that
    /// silently is the one genuinely surprising thing this feature can do.
    public var summary: String {
        switch self {
        case .cream:
            return "The original warm cream and gold. The only theme that follows your Mac's light and dark appearance."
        case .light:
            return "Neutral greys on white. Stays light whatever your Mac is set to."
        case .dark:
            return "Neutral greys on near-black. Stays dark whatever your Mac is set to."
        case .pastel:
            return "Soft blue and rose. Stays fixed whatever your Mac is set to."
        case .champagne:
            return "Cream with champagne gold and a sky-blue tint. Stays fixed whatever your Mac is set to."
        case .sky:
            return "Soft sky blue with a champagne accent. Stays fixed whatever your Mac is set to."
        }
    }

    /// Parse a persisted value, falling back to the default for anything unrecognised so a
    /// hand-edited or stale pref can never leave the UI unstyled.
    public static func parse(_ raw: String?) -> OWTheme {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty, let theme = OWTheme(rawValue: trimmed) else { return .default }
        return theme
    }

    /// The palettes for this theme. Only `.cream` differs between the two — every other theme
    /// returns the same palette for both so it holds its look regardless of system appearance.
    public var palettes: (light: OWPalette, dark: OWPalette) {
        switch self {
        case .cream: return (Self.creamLight, Self.creamDark)
        case .light: return (Self.neutralLight, Self.neutralLight)
        case .dark: return (Self.neutralDark, Self.neutralDark)
        case .pastel: return (Self.pastelPalette, Self.pastelPalette)
        case .champagne: return (Self.champagnePalette, Self.champagnePalette)
        case .sky: return (Self.skyPalette, Self.skyPalette)
        }
    }

    /// True when this theme's surfaces are dark, so AppKit chrome (window appearance, the
    /// overlay's vibrancy material) can be told which way round to render.
    public var prefersDarkChrome: Bool { self == .dark }

    // MARK: - Palettes

    /// Open Whisperer's own identity, unchanged from 1.x.
    static let creamLight = OWPalette(
        page: 0xFAF7F1, surface: 0xFFFFFF, line: 0xDCCFB8,
        ink: 0x2A2520, inkSoft: 0x6A6157, inkFaint: 0x978C7E,
        // accentDeep darkened one notch from the historic 0x98763F: it is used as link text
        // ("Grant") on the white card surface, where the old value scored 4.20:1 — just under
        // the 4.5:1 WCAG AA needs for body text. Same gold, a shade deeper.
        accent: 0xC0A06A, accentDeep: 0x926F3A, onAccent: 0x2A2520,
        pillFill: 0xEADFC8, pickerBg: 0xF3EBDD, pickerBorder: 0xE0D4BD, checkboxBorder: 0xCBBFA9,
        recording: 0xCC3D33, warn: 0xB8822E, live: 0x5E8C4E)

    static let creamDark = OWPalette(
        page: 0x1E1B16, surface: 0x2A2520, line: 0x3A332B,
        ink: 0xF3ECDF, inkSoft: 0xB6AC9C, inkFaint: 0x877D6F,
        accent: 0xCBA86A, accentDeep: 0xD8B677, onAccent: 0x211B12,
        pillFill: 0x342D24, pickerBg: 0x332C23, pickerBorder: 0x423A30, checkboxBorder: 0x4A4136,
        recording: 0xE2675A, warn: 0xE0B25C, live: 0x86C06A)

    /// Authé `:root`. Zero-chroma greys; the page is nudged off pure white so the white cards
    /// still read as raised rather than dissolving into the background.
    static let neutralLight = OWPalette(
        page: 0xFAFAFA, surface: 0xFFFFFF, line: 0xE5E5E5,
        ink: 0x0A0A0A, inkSoft: 0x737373, inkFaint: 0x9A9A9A,
        accent: 0x0A0A0A, accentDeep: 0x262626, onAccent: 0xFAFAFA,
        pillFill: 0xF0F0F0, pickerBg: 0xF5F5F5, pickerBorder: 0xE5E5E5, checkboxBorder: 0xD4D4D4,
        recording: 0xD64545, warn: 0x96691C, live: 0x4F8A3D)

    /// Authé `.dark`, with its chart-palette red/amber/green for status.
    static let neutralDark = OWPalette(
        page: 0x0A0A0A, surface: 0x171717, line: 0x2E2E2E,
        ink: 0xFAFAFA, inkSoft: 0xA1A1A1, inkFaint: 0x7A7A7A,
        accent: 0xFAFAFA, accentDeep: 0xE5E5E5, onAccent: 0x0A0A0A,
        pillFill: 0x262626, pickerBg: 0x262626, pickerBorder: 0x3A3A3A, checkboxBorder: 0x454545,
        recording: 0xE5604D, warn: 0xE0A54D, live: 0x3FB88A)

    /// Authé `.pastel`.
    static let pastelPalette = OWPalette(
        page: 0xEEF6FF, surface: 0xFFFAFC, line: 0xDFD2E2,
        ink: 0x2B3B55, inkSoft: 0x536480, inkFaint: 0x7C8AA0,
        accent: 0x3B5D96, accentDeep: 0x2F4A78, onAccent: 0xFCFCFC,
        pillFill: 0xF3E3EA, pickerBg: 0xE7F0F8, pickerBorder: 0xDFD2E2, checkboxBorder: 0xCBBBD0,
        recording: 0xCC4B4B, warn: 0x96691C, live: 0x4F8A6B)

    /// Authé `.champ` — the brand's champagne gold over cream. Its translucent `rgba` tokens
    /// are flattened here against the cream page, since these surfaces are opaque.
    static let champagnePalette = OWPalette(
        page: 0xFBF4EA, surface: 0xFFFFFF, line: 0xCDE6F5,
        ink: 0x162330, inkSoft: 0x465865, inkFaint: 0x6B7C8E,
        accent: 0xC29E6B, accentDeep: 0x86683C, onAccent: 0x0B1017,
        pillFill: 0xEDF3F5, pickerBg: 0xF2F6F8, pickerBorder: 0xCDE6F5, checkboxBorder: 0xB8D9EC,
        recording: 0xC94A4A, warn: 0x96691C, live: 0x5E8C4E)

    /// Authé `.sky-champ` — sky blue leads and champagne accents, matching the source's
    /// `--primary` / `--accent` split. `accentDeep` carries the champagne (darkened from
    /// `#C29E6B` so it clears AA as link text on the white card surface); an earlier cut used a
    /// darkened sky blue there, which left the theme monochrome despite its name.
    static let skyPalette = OWPalette(
        page: 0xE7F4F9, surface: 0xFFFFFF, line: 0xC5E2F0,
        ink: 0x061D2B, inkSoft: 0x4D616B, inkFaint: 0x74858E,
        accent: 0x87D1E8, accentDeep: 0x86683C, onAccent: 0x061D2B,
        pillFill: 0xDCEEF6, pickerBg: 0xF0F8FB, pickerBorder: 0xC5E2F0, checkboxBorder: 0xAED6E9,
        recording: 0xC94A4A, warn: 0x96691C, live: 0x4F8A6B)
}
