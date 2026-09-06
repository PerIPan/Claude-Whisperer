import Foundation
import OpenWhispererKit

/// Checks for `OverlayStyle` — the overlay analyzer-style pref (led_bars/graph/curtain).
func overlayStyleFailures() -> [String] {
    var failures: [String] = []
    func expect(_ condition: Bool, _ name: String, _ detail: String) {
        if !condition { failures.append("OverlayStyle.\(name): \(detail)") }
    }

    expect(OverlayStyle.parse("wave") == .wave, "parseWave", "got \(OverlayStyle.parse("wave"))")
    expect(OverlayStyle.parse("led_bars") == .ledBars, "parseLed", "got \(OverlayStyle.parse("led_bars"))")
    expect(OverlayStyle.parse("graph") == .graph, "parseGraph", "got \(OverlayStyle.parse("graph"))")
    expect(OverlayStyle.parse("curtain") == .curtain, "parseCurtain", "got \(OverlayStyle.parse("curtain"))")
    expect(OverlayStyle.parse(" curtain\n") == .curtain, "trims", "got \(OverlayStyle.parse(" curtain\n"))")
    expect(OverlayStyle.parse(nil) == .wave, "nilDefault", "got \(OverlayStyle.parse(nil))")
    expect(OverlayStyle.parse("vintage") == .wave, "garbageDefault", "got \(OverlayStyle.parse("vintage"))")
    expect(OverlayStyle.parse("") == .wave, "emptyDefault", "got \(OverlayStyle.parse(""))")
    expect(OverlayStyle.defaultStyle == .wave, "default", "got \(OverlayStyle.defaultStyle)")

    // `usesSpectrumBands` gates whether the audio taps run the 96-band filterbank at all
    // (SpectrumGate). Getting it wrong in one direction silently blanks an analyzer style;
    // in the other it reinstates ~1% of a core burning on bands nothing reads. Enumerated
    // over `allCases` rather than restated as `!= .wave`, so a new style has to be
    // classified here instead of silently inheriting whichever answer the expression gives.
    let spectrumStyles: Set<OverlayStyle> = [.ledBars, .graph, .curtain]
    for style in OverlayStyle.allCases {
        let expected = spectrumStyles.contains(style)
        expect(style.usesSpectrumBands == expected,
               "usesSpectrumBands.\(style.rawValue)",
               "expected \(expected), got \(style.usesSpectrumBands)")
    }
    expect(!OverlayStyle.defaultStyle.usesSpectrumBands,
           "defaultStyleSkipsBands",
           "the default style must not pay for the filterbank; got \(OverlayStyle.defaultStyle)")
    expect(spectrumStyles.count == OverlayStyle.allCases.count - 1,
           "spectrumStyleCoverage",
           "allCases has \(OverlayStyle.allCases.count); classify the new style here")

    return failures
}
