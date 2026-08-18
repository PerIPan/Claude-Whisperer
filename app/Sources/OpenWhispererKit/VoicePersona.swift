import Foundation

/// The national-character persona a Kokoro voice carries into spoken replies.
///
/// `hooks/voice-shared.sh`'s `resolve_flavor()` adds an ungated persona line to the nudge for
/// every personified voice — so picking `ff_siwis` doesn't just change the accent, it tells the
/// model to be "dry and faintly unimpressed" on every spoken turn. That is a real, ongoing
/// change to how replies sound, and until this type existed it was disclosed nowhere: the map
/// lived only in bash, and Settings never mentioned it.
///
/// This is the **display** half. The hook remains the only thing that steers the model; nothing
/// here is read at nudge time. `HookTests.voicePersonaParityFailures()` parses `resolve_flavor()`
/// and fails if the two ever drift, which is the same guarantee `VoiceLanguageParityChecks`
/// gives the language map.
///
/// Keyed on the voice id's **first character**, exactly as the hook is (`${voice:0:1}`). No
/// `isSupertonic` guard: a `supertonic:nl:F1` id starts with `s`, which is not a key, so it
/// falls out as `nil` for the same reason it does in bash. Adding a guard here would make Swift
/// stricter than the hook and put the two out of parity in the one case the test cannot see.
public enum VoicePersona {
    public struct Persona: Equatable, Sendable {
        /// How the voice sounds — "American English". Full language name, as the hook phrases it.
        public let accent: String
        /// The character adopted — "American". Bare nationality, not the language name.
        public let name: String
        /// The character itself, lowercase and mid-sentence: "quietly self-assured, …".
        public let descriptor: String

        /// "a" or "an" for `name`. Two of the nine ("American", "Italian") are vowel-initial,
        /// so a hardcoded "a" is wrong often enough to notice. Every persona name here is
        /// English and unambiguous on its first letter, so this need not handle the
        /// "an hour" / "a university" exceptions.
        public var article: String {
            "aeiouAEIOU".contains(name.first ?? "x") ? "an" : "a"
        }

        public init(accent: String, name: String, descriptor: String) {
            self.accent = accent
            self.name = name
            self.descriptor = descriptor
        }
    }

    /// Mirrors `resolve_flavor()`'s case arms verbatim. Reword in `voice-shared.sh` first —
    /// that copy is what the model is actually told — then bring this one along; `HookTests`
    /// fails until they match.
    public static let byPrefix: [Character: Persona] = [
        "a": Persona(accent: "American English", name: "American",
                     descriptor: "quietly self-assured, with a light touch of Silicon Valley hype"),
        "b": Persona(accent: "British English", name: "British",
                     descriptor: "dry and unflappable, with a streak of deadpan wit and gentle irony"),
        "f": Persona(accent: "French", name: "French",
                     descriptor: "dry and faintly unimpressed, given to the occasional philosophical shrug"),
        "i": Persona(accent: "Italian", name: "Italian",
                     descriptor: "warm and expressive; things are either wonderful or a small catastrophe, rarely in between"),
        "e": Persona(accent: "Spanish", name: "Spanish",
                     descriptor: "relaxed and direct; there's always time, and it'll all be fine"),
        "p": Persona(accent: "Brazilian Portuguese", name: "Brazilian",
                     descriptor: "sunny and easygoing, unbothered, always a friendly way around things"),
        "h": Persona(accent: "Hindi", name: "Hindi",
                     descriptor: "warm and irrepressibly helpful, the eternal problem-solver, assuring you it's no trouble at all"),
        "j": Persona(accent: "Japanese", name: "Japanese",
                     descriptor: "courteous and understated, meticulous, softening things, quietly prizing care and subtlety"),
        "z": Persona(accent: "Mandarin Chinese", name: "Chinese",
                     descriptor: "pragmatic and modest, understated, fond of a proverb, unfussed by small things"),
    ]

    /// The persona for a voice id, or `nil` when it carries none (every Supertonic voice, and
    /// any Kokoro prefix the hook has no arm for).
    public static func forVoice(_ voiceID: String) -> Persona? {
        guard let first = voiceID.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return byPrefix[first]
    }

    /// One sentence for Settings, phrased so the trade is legible at a glance: what changes
    /// (tone) and what does not (the work). Deliberately not the nudge's wording — that one
    /// is an instruction to a model, this one is a disclosure to a person.
    public static func disclosure(for voiceID: String) -> String? {
        guard let persona = forVoice(voiceID) else { return nil }
        return "Spoken replies take on \(persona.article) \(persona.name) persona — \(persona.descriptor). "
            + "Tone only: it never changes what gets done, or your on-screen reply."
    }
}
