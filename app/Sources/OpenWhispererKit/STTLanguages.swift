import Foundation

/// How much confidence we have in Whisper's output for a language.
///
/// Derived from OpenAI's published `language-breakdown.svg` for large-v3 (the per-language
/// chart in the whisper README), which plots Common Voice 15 and FLEURS side by side and
/// includes only languages under 60% error. Each language is taken at its better result of
/// the two. See `docs/superpowers/specs/2026-08-01-full-language-rosters-design.md` for the
/// full table and how the numbers were recovered — do NOT re-derive them.
public enum STTTier: String, Sendable, Equatable, CaseIterable {
    /// Measured at or below `STTLanguages.limitedThreshold` error.
    case good
    /// Measured above the threshold. Usable for short phrases; expect to correct.
    case limited
    /// Absent from OpenAI's chart, so either above 60% error or never benchmarked.
    /// Not the same as "known bad" — Faroese and Occitan are simply not in either corpus.
    case untested
}

/// A language Whisper can be asked to transcribe.
public struct STTLanguage: Sendable, Equatable {
    /// Whisper language code, lowercase (`el`, `yue`). Written verbatim to `stt_language`
    /// and handed to `DecodingOptions.language`.
    public let code: String
    /// Display name, title-cased. WhisperKit's own names are lowercase and carry aliases
    /// (`castilian`/`spanish`); one canonical name per code is chosen here.
    public let name: String
    /// Published error rate, or nil when OpenAI published none.
    ///
    /// WER for most languages but **CER** for `zh`, `yue`, `ja`, `ko`, `th`, so those five
    /// are not strictly comparable to the rest. None is near the threshold, so the tier
    /// split is unaffected.
    public let errorRate: Double?

    public init(code: String, name: String, errorRate: Double?) {
        self.code = code
        self.name = name
        self.errorRate = errorRate
    }

    /// Computed, never stored, so the tier and the number can never disagree.
    public var tier: STTTier {
        guard let errorRate else { return .untested }
        return errorRate <= STTLanguages.limitedThreshold ? .good : .limited
    }
}

/// The dictation language roster: every code WhisperKit accepts, tiered by measured quality.
///
/// Pure and dependency-free so it unit-tests under Command Line Tools; the app target
/// intersects it with `WhisperKit.Constants.languageCodes` before display, so the UI can
/// only ever shrink toward what the decoder actually knows.
///
/// large-v3-turbo is a single multilingual model — every code here already worked before
/// this table existed. Listing a language downloads nothing.
public enum STTLanguages {
    /// Sentinel written to `stt_language` for "let Whisper guess". `DictationManager`
    /// treats it (and an empty file) as nil, which turns `detectLanguage` on.
    public static let autoCode = "auto"

    /// Error rate above which a language is shown under "Limited accuracy". Above roughly
    /// this, two words in five are wrong and correcting costs more than typing would have.
    /// A boundary for presentation only — nothing is hidden, so being slightly off is
    /// cosmetic. Owner-set 2026-08-01.
    public static let limitedThreshold: Double = 35.0

    /// Shown first, above the full roster. The list Settings offered before it grew to all
    /// 100, in its original order, so existing muscle memory still works. These also appear
    /// in their tier below — the duplication is deliberate and stated in the UI caption.
    public static let common: [String] = [
        "en", "es", "fr", "de", "it", "pt", "nl", "ja", "ko", "zh",
        "ar", "hi", "ru", "pl", "tr", "uk", "sv",
    ]

    /// All 100, alphabetical by display name.
    public static let all: [STTLanguage] = {
        func L(_ c: String, _ n: String, _ e: Double?) -> STTLanguage {
            STTLanguage(code: c, name: n, errorRate: e)
        }
        return [
        L("af", "Afrikaans", 32.4),
        L("sq", "Albanian", 55.7),
        L("am", "Amharic", nil),
        L("ar", "Arabic", 9.6),
        L("hy", "Armenian", 42.2),
        L("as", "Assamese", nil),
        L("az", "Azerbaijani", 19.7),
        L("ba", "Bashkir", nil),
        L("eu", "Basque", 38.9),
        L("be", "Belarusian", 42.5),
        L("bn", "Bengali", 40.3),
        L("bs", "Bosnian", 13.0),
        L("br", "Breton", nil),
        L("bg", "Bulgarian", 12.5),
        L("my", "Burmese", nil),
        L("yue", "Cantonese", 10.9),
        L("ca", "Catalan", 4.8),
        L("zh", "Chinese", 7.7),
        L("hr", "Croatian", 10.8),
        L("cs", "Czech", 9.0),
        L("da", "Danish", 12.0),
        L("nl", "Dutch", 4.3),
        L("en", "English", 4.1),
        L("et", "Estonian", 18.1),
        L("fo", "Faroese", nil),
        L("tl", "Filipino", 13.0),
        L("fi", "Finnish", 7.7),
        L("fr", "French", 5.3),
        L("gl", "Galician", 13.1),
        L("ka", "Georgian", nil),
        L("de", "German", 4.9),
        L("el", "Greek", 10.9),
        L("gu", "Gujarati", 47.4),
        L("ht", "Haitian Creole", nil),
        L("ha", "Hausa", nil),
        L("haw", "Hawaiian", nil),
        L("he", "Hebrew", 23.5),
        L("hi", "Hindi", 16.9),
        L("hu", "Hungarian", 12.9),
        L("is", "Icelandic", 30.4),
        L("id", "Indonesian", 6.1),
        L("it", "Italian", 3.0),
        L("ja", "Japanese", 4.9),
        L("jw", "Javanese", nil),
        L("kn", "Kannada", 33.0),
        L("kk", "Kazakh", 32.4),
        L("km", "Khmer", nil),
        L("ko", "Korean", 3.1),
        L("lo", "Lao", nil),
        L("la", "Latin", nil),
        L("lv", "Latvian", 16.7),
        L("ln", "Lingala", nil),
        L("lt", "Lithuanian", 23.7),
        L("lb", "Luxembourgish", nil),
        L("mk", "Macedonian", 14.7),
        L("mg", "Malagasy", nil),
        L("ms", "Malay", 7.3),
        L("ml", "Malayalam", nil),
        L("mt", "Maltese", nil),
        L("mi", "Maori", 39.8),
        L("mr", "Marathi", 34.1),
        L("mn", "Mongolian", nil),
        L("ne", "Nepali", 40.2),
        L("no", "Norwegian", 7.8),
        L("nn", "Norwegian Nynorsk", 30.7),
        L("oc", "Occitan", nil),
        L("ps", "Pashto", nil),
        L("fa", "Persian", 29.4),
        L("pl", "Polish", 4.6),
        L("pt", "Portuguese", 4.1),
        L("pa", "Punjabi", 34.7),
        L("ro", "Romanian", 8.2),
        L("ru", "Russian", 5.0),
        L("sa", "Sanskrit", nil),
        L("sr", "Serbian", 11.6),
        L("sn", "Shona", nil),
        L("sd", "Sindhi", nil),
        L("si", "Sinhala", nil),
        L("sk", "Slovak", 9.2),
        L("sl", "Slovenian", 16.8),
        L("so", "Somali", nil),
        L("es", "Spanish", 2.8),
        L("su", "Sundanese", nil),
        L("sw", "Swahili", 34.1),
        L("sv", "Swedish", 7.6),
        L("tg", "Tajik", nil),
        L("ta", "Tamil", 18.3),
        L("tt", "Tatar", nil),
        L("te", "Telugu", 39.3),
        L("th", "Thai", 5.8),
        L("bo", "Tibetan", nil),
        L("tr", "Turkish", 6.7),
        L("tk", "Turkmen", nil),
        L("uk", "Ukrainian", 6.4),
        L("ur", "Urdu", 20.4),
        L("uz", "Uzbek", nil),
        L("vi", "Vietnamese", 8.6),
        L("cy", "Welsh", 28.6),
        L("yi", "Yiddish", nil),
        L("yo", "Yoruba", nil),
        ]
    }()

    public static func language(code: String) -> STTLanguage? {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.code == c }
    }

    public static func tiered(_ tier: STTTier) -> [STTLanguage] {
        all.filter { $0.tier == tier }
    }

    /// Case-insensitive find-as-you-type: substring on the display name, prefix on the code.
    ///
    /// Code matching is prefix-only on purpose — a substring match would make the two-letter
    /// query "el" hit every code containing those letters, burying Greek in noise.
    /// An empty query returns `langs` unchanged.
    public static func match(_ langs: [STTLanguage], query: String) -> [STTLanguage] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return langs }
        return langs.filter { $0.name.lowercased().contains(q) || $0.code.hasPrefix(q) }
    }

    /// What to store for `stt_language` given what is already there; nil means leave it be.
    ///
    /// English replaces Auto-detect as the default (2026-08-01, owner decision). Detection
    /// costs a decoder pass and is least reliable on exactly the short clips dictation
    /// produces, and the owner measured fewer errors with English set explicitly.
    /// **Do not restore Auto-detect as the default.**
    ///
    /// Only ever fires when nothing is stored. A stored `auto` is a real choice and is left
    /// alone, so this cannot un-pick Auto-detect from a user who wanted it.
    public static func defaultedLanguage(existing: String?) -> String? {
        let stored = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? "en" : nil
    }
}
