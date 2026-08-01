import Foundation
import OpenWhispererKit

/// Guards the dictation roster: the table shape, the tier split, search, and the
/// English-default migration. The counts below come from OpenAI's published large-v3
/// chart (see the design spec) — if one changes, the table changed, not the test.
func sttLanguageFailures() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool) {
        if !ok { failures.append("STTLanguages: \(label)") }
    }

    let all = STTLanguages.all

    // Shape
    check("all has 100 entries (got \(all.count))", all.count == 100)
    check("codes are unique", Set(all.map(\.code)).count == all.count)
    check("codes are lowercase", all.allSatisfy { $0.code == $0.code.lowercased() })
    check("names are non-empty", all.allSatisfy { !$0.name.isEmpty })
    check("no 'auto' entry — it is a sentinel, not a language",
          !all.contains { $0.code == STTLanguages.autoCode })
    check("sorted alphabetically by name", all.map(\.name) == all.map(\.name).sorted())

    // Tier split
    let good = STTLanguages.tiered(.good)
    let limited = STTLanguages.tiered(.limited)
    let untested = STTLanguages.tiered(.untested)
    check("56 good (got \(good.count))", good.count == 56)
    check("9 limited (got \(limited.count))", limited.count == 9)
    check("35 untested (got \(untested.count))", untested.count == 35)
    check("tiers partition the table",
          good.count + limited.count + untested.count == all.count)

    // Tier agrees with the number it is derived from
    for lang in all {
        switch (lang.errorRate, lang.tier) {
        case (nil, .untested): continue
        case (let rate?, .good) where rate <= STTLanguages.limitedThreshold: continue
        case (let rate?, .limited) where rate > STTLanguages.limitedThreshold: continue
        default:
            failures.append("STTLanguages: \(lang.code) tier \(lang.tier) disagrees with errorRate \(String(describing: lang.errorRate))")
        }
    }
    check("untested languages carry no error rate",
          untested.allSatisfy { $0.errorRate == nil })

    // Spot-checks across all three tiers
    check("Greek is good at 10.9", STTLanguages.language(code: "el").map {
        $0.tier == .good && $0.errorRate == 10.9 && $0.name == "Greek"
    } == true)
    check("Albanian is limited at 55.7", STTLanguages.language(code: "sq").map {
        $0.tier == .limited && $0.errorRate == 55.7
    } == true)
    check("Lingala is untested", STTLanguages.language(code: "ln").map {
        $0.tier == .untested && $0.errorRate == nil
    } == true)
    check("Cantonese is its own entry, distinct from Chinese",
          STTLanguages.language(code: "yue") != nil && STTLanguages.language(code: "zh") != nil)
    check("code lookup tolerates case and padding",
          STTLanguages.language(code: "  EL ")?.code == "el")

    // The pinned shortlist
    check("common has 17 codes (got \(STTLanguages.common.count))",
          STTLanguages.common.count == 17)
    check("every common code exists in all",
          STTLanguages.common.allSatisfy { code in all.contains { $0.code == code } })
    check("every common language is in the good tier",
          STTLanguages.common.allSatisfy { STTLanguages.language(code: $0)?.tier == .good })
    check("common has no duplicates",
          Set(STTLanguages.common).count == STTLanguages.common.count)

    // Search semantics live in `PickerSearchChecks`, against the predicate the picker runs.

    // Default-language migration
    check("nothing stored defaults to English",
          STTLanguages.defaultedLanguage(existing: nil) == "en")
    check("empty file defaults to English",
          STTLanguages.defaultedLanguage(existing: "") == "en")
    check("whitespace-only file defaults to English",
          STTLanguages.defaultedLanguage(existing: "  \n ") == "en")
    // A stored "auto" is a deliberate choice; the migration must never overwrite it.
    check("stored auto is left alone",
          STTLanguages.defaultedLanguage(existing: "auto") == nil)
    check("stored language is left alone",
          STTLanguages.defaultedLanguage(existing: "el") == nil)
    check("stored English is left alone",
          STTLanguages.defaultedLanguage(existing: "en") == nil)

    return failures
}
