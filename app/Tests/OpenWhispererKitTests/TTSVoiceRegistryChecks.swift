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
    // Every Supertonic language Kokoro can't speak (24) × two styles (F1/M1).
    if supertonic.count != 48 {
        failures.append("TTSVoiceRegistry: expected 48 Supertonic voices, got \(supertonic.count)")
    }
    let supertonicLanguages = Set(supertonic.compactMap { TTSVoiceRouter.route($0.id).language })
    if supertonicLanguages.count != 24 {
        failures.append("TTSVoiceRegistry: expected 24 Supertonic languages, got \(supertonicLanguages.count)")
    }
    // Every one must be a language the router actually accepts, or the voice silently
    // falls back to an English Kokoro voice at synthesis time.
    for language in supertonicLanguages where !TTSVoiceRouter.supertonicLanguages.contains(language) {
        failures.append("TTSVoiceRegistry: '\(language)' is not in TTSVoiceRouter.supertonicLanguages")
    }
    // The seven languages Kokoro also covers stay Kokoro-only, so the picker never shows
    // one language twice and never asks the user to pick an engine.
    for overlap in ["en", "es", "fr", "it", "pt", "hi", "ja"] where supertonicLanguages.contains(overlap) {
        failures.append("TTSVoiceRegistry: '\(overlap)' is Kokoro's — it must not also have a Supertonic group")
    }
    // Supertonic was never trained on Mandarin; zh must stay with Kokoro's z* voices.
    if supertonicLanguages.contains("zh") {
        failures.append("TTSVoiceRegistry: Supertonic has no Mandarin — zh must route to Kokoro")
    }

    // One group per language: a duplicate would split a language's voices across two
    // sections of the picker.
    let groupNames = TTSVoiceRegistry.groups.map(\.name)
    if Set(groupNames).count != groupNames.count {
        failures.append("TTSVoiceRegistry: duplicate group names present")
    }
    // Each Supertonic group is exactly one female and one male style.
    for group in TTSVoiceRegistry.groups where group.voices.allSatisfy({ TTSVoiceRouter.isSupertonic($0.id) }) {
        if group.voices.count != 2 || Set(group.voices.map(\.gender)) != ["Female", "Male"] {
            failures.append("TTSVoiceRegistry: Supertonic group '\(group.name)' is not one F1 + one M1")
        }
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
    // Greek is the language the 2026-08-01 widening was asked for; assert it the same way.
    if !all.contains(where: { $0.id == "supertonic:el:F1" && $0.language == "Greek" }) {
        failures.append("TTSVoiceRegistry: missing the Greek supertonic:el:F1 voice")
    }
    if TTSVoiceRouter.route("supertonic:el:M1").language != "el" {
        failures.append("TTSVoiceRegistry: supertonic:el:M1 does not route to Greek")
    }

    // Ids must be unique — duplicates would make the Settings picker ambiguous.
    let ids = all.map(\.id)
    if Set(ids).count != ids.count {
        failures.append("TTSVoiceRegistry: duplicate voice ids present")
    }

    return failures
}
