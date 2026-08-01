import Foundation
import OpenWhispererKit

func owThemeFailures() -> [String] {
    var failures: [String] = []

    // Persisted values round-trip, and anything unrecognised falls back rather than leaving
    // the UI unstyled.
    for theme in OWTheme.allCases {
        if OWTheme.parse(theme.rawValue) != theme {
            failures.append("OWTheme.parse round-trip failed for '\(theme.rawValue)'")
        }
    }
    for raw in ["CREAM", " dark\n", "Sky"] where OWTheme.parse(raw) == .cream && raw != "CREAM" {
        // case/whitespace normalisation should resolve these to a real theme
        failures.append("OWTheme.parse did not normalise '\(raw)'")
    }
    if OWTheme.parse("CREAM") != .cream { failures.append("OWTheme.parse: uppercase cream") }
    if OWTheme.parse(" dark\n") != .dark { failures.append("OWTheme.parse: whitespace dark") }
    for raw in [nil, "", "   ", "nonsense", "solarized"] {
        if OWTheme.parse(raw) != .default {
            failures.append("OWTheme.parse(\(raw ?? "nil")) should fall back to the default")
        }
    }
    if OWTheme.default != .champagne {
        failures.append("OWTheme.default should be .champagne (the brand palette) as of 2.0.1")
    }

    // Cream is the only theme that tracks the system appearance; every other theme must hold
    // its look, so its two palettes are identical.
    if OWTheme.cream.palettes.light == OWTheme.cream.palettes.dark {
        failures.append("OWTheme.cream must differ between light and dark")
    }
    for theme in OWTheme.allCases where theme != .cream {
        if theme.palettes.light != theme.palettes.dark {
            failures.append("OWTheme.\(theme.rawValue) must not vary with system appearance")
        }
    }

    // Only the dark theme asks AppKit for dark chrome; cream follows the system via a nil
    // appearance, so flagging it here would force it permanently dark.
    for theme in OWTheme.allCases {
        let expected = (theme == .dark)
        if theme.prefersDarkChrome != expected {
            failures.append("OWTheme.\(theme.rawValue).prefersDarkChrome should be \(expected)")
        }
    }

    // Every palette must be legible: page and ink can't collide, and no token may be left at
    // an unset-looking default. A theme that shipped with page == ink would be unreadable.
    for theme in OWTheme.allCases {
        for (name, p) in [("light", theme.palettes.light), ("dark", theme.palettes.dark)] {
            if p.page == p.ink {
                failures.append("OWTheme.\(theme.rawValue) [\(name)]: page and ink are identical")
            }
            if p.accent == p.onAccent {
                failures.append("OWTheme.\(theme.rawValue) [\(name)]: accent and onAccent collide")
            }
            // Crude contrast guard: the page and ink must differ substantially in luminance.
            if luminanceGap(p.page, p.ink) < 0.35 {
                failures.append(
                    "OWTheme.\(theme.rawValue) [\(name)]: page/ink contrast too low "
                        + "(\(String(format: "%.2f", luminanceGap(p.page, p.ink))))")
            }
            if luminanceGap(p.accent, p.onAccent) < 0.35 {
                failures.append(
                    "OWTheme.\(theme.rawValue) [\(name)]: accent/onAccent contrast too low "
                        + "(\(String(format: "%.2f", luminanceGap(p.accent, p.onAccent))))")
            }

            // `accentDeep` is used as link text ("Grant") directly on `surface`, and `warn` as a
            // status colour on `page`. Both are real text/UI colours, so hold them to WCAG
            // ratios rather than the cruder luminance gap above — a too-pale gold link on a
            // white card shipped once and only turned up in review.
            if contrastRatio(p.accentDeep, p.surface) < 4.5 {
                failures.append(
                    "OWTheme.\(theme.rawValue) [\(name)]: accentDeep on surface is "
                        + "\(String(format: "%.2f", contrastRatio(p.accentDeep, p.surface))):1, "
                        + "below the 4.5:1 needed for body text")
            }
            if contrastRatio(p.warn, p.page) < 3.0 {
                failures.append(
                    "OWTheme.\(theme.rawValue) [\(name)]: warn on page is "
                        + "\(String(format: "%.2f", contrastRatio(p.warn, p.page))):1, "
                        + "below the 3:1 needed for a UI indicator")
            }
        }
    }

    // Labels are user-facing and must be distinct + non-empty.
    let labels = OWTheme.allCases.map(\.label)
    if Set(labels).count != labels.count { failures.append("OWTheme labels are not unique") }
    if labels.contains(where: \.isEmpty) { failures.append("OWTheme has an empty label") }
    if OWTheme.allCases.contains(where: { $0.summary.isEmpty }) {
        failures.append("OWTheme has an empty summary")
    }

    return failures
}

/// Relative-luminance difference between two 0xRRGGBB colours, 0…1.
private func luminanceGap(_ a: UInt32, _ b: UInt32) -> Double {
    abs(relativeLuminance(a) - relativeLuminance(b))
}

/// WCAG contrast ratio between two 0xRRGGBB colours, 1…21.
private func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
    let la = relativeLuminance(a), lb = relativeLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

private func relativeLuminance(_ hex: UInt32) -> Double {
    func channel(_ raw: UInt32) -> Double {
        let c = Double(raw) / 255.0
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    let r = channel((hex >> 16) & 0xFF)
    let g = channel((hex >> 8) & 0xFF)
    let b = channel(hex & 0xFF)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
