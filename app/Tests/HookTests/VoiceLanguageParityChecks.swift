import Foundation
import OpenWhispererKit

/// Cross-target parity: every Supertonic language the Settings picker offers must be a
/// language `resolve_language_line()` knows, under the *same* display name.
///
/// Two things drift apart otherwise. If the hook has no case for a code it emits no line
/// at all, so the model writes English and a Greek voice reads it aloud — the exact
/// failure Supertonic-3 was added to fix, and silent. And if the two spell a language
/// differently, the Voice tab's caption ("Replies will be spoken in Portuguese")
/// contradicts the nudge the model actually received.
///
/// This lives in `HookTests` because it is the only runner that can see both sides: it
/// depends on `OpenWhispererKit` *and* can read `hooks/voice-shared.sh`. The map stays in
/// bash — this asserts agreement rather than moving it.
func voiceLanguageParityFailures() -> [String] {
    var failures: [String] = []

    let sharedPath = Hook.hooksDir.appendingPathComponent("voice-shared.sh")
    guard let shared = try? String(contentsOf: sharedPath, encoding: .utf8) else {
        return ["voice-shared.sh could not be read at \(sharedPath.path)"]
    }

    // Scope to resolve_language_line's body before parsing: an unrelated `xx) language="…"`
    // elsewhere in the file would otherwise be absorbed into the map. The map is a bash
    // `case` of `code) language="Name" ;;` arms; `VoiceSharedMaps` is the one parser, shared
    // with the Pi mirror's check, so this stays a parity check instead of a second copy.
    guard let body = VoiceSharedMaps.body(of: "resolve_language_line", in: shared) else {
        return ["voice-shared.sh: resolve_language_line() not found — did it get renamed?"]
    }
    let hookNames = VoiceSharedMaps.languages(inLanguageBody: body)

    if hookNames.isEmpty {
        return ["voice-shared.sh: resolve_language_line's case arms did not parse — did the map's shape change?"]
    }

    for group in TTSVoiceRegistry.groups {
        // Kokoro groups are named by region ("English (US)"), not by the language codes
        // this map keys on, and they never receive a language line.
        let languages = Set(group.voices.compactMap { TTSVoiceRouter.route($0.id).language })
        guard languages.count == 1, let code = languages.first else { continue }

        guard let hookName = hookNames[code] else {
            failures.append("voice-shared.sh: no language line for '\(code)' (\(group.name)) — that voice would read English")
            continue
        }
        if hookName != group.name {
            failures.append("language name mismatch for '\(code)': registry says '\(group.name)', hook says '\(hookName)'")
        }
    }

    // Greek is the language the 2026-08-01 widening was requested for; assert it directly
    // so a regression names it rather than showing up only as a count.
    if hookNames["el"] != "Greek" {
        failures.append("voice-shared.sh: expected el -> Greek, got \(hookNames["el"] ?? "nothing")")
    }

    return failures
}
