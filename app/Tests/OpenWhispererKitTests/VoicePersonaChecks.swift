import Foundation
import OpenWhispererKit

/// Guards the persona disclosure. Whether a persona is *well written* is a review concern;
/// what a test can prove is that the right voices get one, the wrong ones don't, and the
/// sentence shown to the user is actually about the voice they picked.
///
/// Parity with `resolve_flavor()` is asserted separately, in `HookTests` — only that runner
/// can read the bash side.
func voicePersonaFailures() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool) {
        if !ok { failures.append("VoicePersona: \(label)") }
    }

    // Every Kokoro voice the picker offers carries a persona, because the hook keys on the
    // same first character. A voice in the roster with no persona would be one whose tone
    // changes with nothing said about it.
    for voice in TTSVoiceRegistry.allVoices where !TTSVoiceRouter.isSupertonic(voice.id) {
        check("\(voice.id) has a persona", VoicePersona.forVoice(voice.id) != nil)
    }

    // Supertonic voices get the reply-language line *instead of* a persona. Disclosing one
    // for them would describe a nudge the model never receives.
    for voice in TTSVoiceRegistry.allVoices where TTSVoiceRouter.isSupertonic(voice.id) {
        check("\(voice.id) has no persona", VoicePersona.forVoice(voice.id) == nil)
    }

    // Spot-check the mapping itself, so a regression names the voice rather than a count.
    check("af_heart is American", VoicePersona.forVoice("af_heart")?.name == "American")
    check("bm_george is British", VoicePersona.forVoice("bm_george")?.name == "British")
    check("ff_siwis is French", VoicePersona.forVoice("ff_siwis")?.name == "French")
    check("jf_alpha is Japanese", VoicePersona.forVoice("jf_alpha")?.name == "Japanese")
    check("zm_yunxi is Chinese", VoicePersona.forVoice("zm_yunxi")?.name == "Chinese")

    // Accent and persona name are different strings for the English voices and must stay so:
    // the accent is a language ("American English"), the persona a nationality ("American").
    check("af_heart accent is the language name",
          VoicePersona.forVoice("af_heart")?.accent == "American English")

    // The hook trims whitespace off the stored voice before matching; a stray newline in
    // `tts_voice` must not silently drop the disclosure while the model still gets the persona.
    check("a trailing newline still resolves", VoicePersona.forVoice("af_heart\n")?.name == "American")

    // Unknown and empty inputs fall out rather than defaulting to a persona.
    check("unknown prefix has none", VoicePersona.forVoice("qq_nobody") == nil)
    check("empty id has none", VoicePersona.forVoice("") == nil)
    check("supertonic id has none", VoicePersona.forVoice("supertonic:nl:F1") == nil)

    // The disclosure sentence must name the persona and disclaim scope — those two clauses
    // are the whole point of showing it.
    if let line = VoicePersona.disclosure(for: "ff_siwis") {
        check("disclosure names the persona", line.contains("French"))
        check("disclosure carries the descriptor", line.contains("philosophical shrug"))
        check("disclosure disclaims scope", line.contains("Tone only"))
    } else {
        failures.append("VoicePersona: ff_siwis produced no disclosure")
    }
    check("no disclosure without a persona", VoicePersona.disclosure(for: "supertonic:nl:F1") == nil)

    // Article agreement. "a American" / "a Italian" is the whole reason `article` exists, and
    // it is the kind of wrong that undermines a sentence whose job is to sound considered.
    check("American takes 'an'",
          VoicePersona.disclosure(for: "af_heart")?.contains("an American persona") == true)
    check("Italian takes 'an'",
          VoicePersona.disclosure(for: "if_sara")?.contains("an Italian persona") == true)
    check("British takes 'a'",
          VoicePersona.disclosure(for: "bm_george")?.contains("a British persona") == true)
    // Catches a new vowel-initial persona added without thinking about the article.
    for voice in TTSVoiceRegistry.allVoices where !TTSVoiceRouter.isSupertonic(voice.id) {
        guard let line = VoicePersona.disclosure(for: voice.id) else { continue }
        let slip = [" a A", " a E", " a I", " a O", " a U"].contains { line.contains($0) }
        check("\(voice.id) has no 'a <vowel>' slip", !slip)
    }

    return failures
}
