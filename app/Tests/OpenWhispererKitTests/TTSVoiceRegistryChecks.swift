import Foundation
import OpenWhispererKit

func ttsVoiceRegistryFailures() -> [String] {
    var failures: [String] = []
    let all = TTSVoiceRegistry.allVoices

    let kokoro = all.filter { TTSVoiceRouter.route($0.id).engine == .kokoro }
    let supertonic = all.filter { TTSVoiceRouter.route($0.id).engine == .supertonic }

    if kokoro.count != 54 {
        failures.append("TTSVoiceRegistry: expected 54 Kokoro voices, got \(kokoro.count)")
    }
    // Five curated languages × two styles (F1/M1).
    if supertonic.count != 10 {
        failures.append("TTSVoiceRegistry: expected 10 Supertonic voices, got \(supertonic.count)")
    }
    if !all.contains(where: { $0.id == "af_heart" && $0.gender == "Female" && $0.region == "US" }) {
        failures.append("TTSVoiceRegistry.allVoices: missing af_heart or properties mismatched")
    }

    // Every registry id must round-trip through the router to the engine it belongs to — a
    // typo'd Supertonic id would otherwise silently fall back to an English Kokoro voice,
    // which is exactly the bug this feature exists to fix.
    for voice in supertonic {
        let route = TTSVoiceRouter.route(voice.id)
        if route.language == nil {
            failures.append("TTSVoiceRegistry: \(voice.id) routed to Supertonic with no language")
        }
        if !TTSVoiceRouter.supertonicStyles.contains(route.voice) {
            failures.append("TTSVoiceRegistry: \(voice.id) has unknown style '\(route.voice)'")
        }
    }

    // Dutch is the language this shipped for; assert it concretely rather than by count alone.
    if !all.contains(where: { $0.id == "supertonic:nl:F1" && $0.language == "Dutch" }) {
        failures.append("TTSVoiceRegistry: missing the Dutch supertonic:nl:F1 voice")
    }

    // Ids must be unique — duplicates would make the Settings picker ambiguous.
    let ids = all.map(\.id)
    if Set(ids).count != ids.count {
        failures.append("TTSVoiceRegistry: duplicate voice ids present")
    }

    return failures
}
