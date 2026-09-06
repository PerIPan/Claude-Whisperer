import Foundation

/// Overlay analyzer style pref (`overlay_style` flat file). Same parse-with-default
/// shape as `TTSSpeed`: bad/missing input never breaks the overlay.
public enum OverlayStyle: String, CaseIterable {
    case wave                       // 1.6.0 mirrored-line waveform + status dot (the default)
    case ledBars = "led_bars"
    case graph
    case curtain

    public static let defaultStyle: OverlayStyle = .wave

    /// Whether this style renders `SpectrumBands` output.
    ///
    /// `.wave` draws `AudioRecorder.levelHistory` instead and never reads the bands, so
    /// for the default style the 96-band filterbank both audio taps run is pure waste.
    /// `SpectrumGate` consults this to skip the analysis when nothing will display it.
    ///
    /// Exhaustive on purpose: written as `self != .wave` a new case would silently inherit
    /// "yes", and the only thing catching it would be a test suite this project runs by hand.
    public var usesSpectrumBands: Bool {
        switch self {
        case .wave: return false
        case .ledBars, .graph, .curtain: return true
        }
    }

    /// Trims and parses a raw pref-file string; anything unrecognized → default.
    public static func parse(_ raw: String?) -> OverlayStyle {
        guard let raw else { return defaultStyle }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return OverlayStyle(rawValue: trimmed) ?? defaultStyle
    }
}
