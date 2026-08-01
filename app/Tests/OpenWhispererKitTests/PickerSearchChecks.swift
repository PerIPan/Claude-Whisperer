import Foundation
import OpenWhispererKit

/// Guards the predicate `OWSearchablePicker` actually runs. Previously the picker had its
/// own inline copy of these rules and the tested function was unreachable from the UI —
/// this file exists because that split was caught in review.
func pickerSearchFailures() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool) {
        if !ok { failures.append("PickerSearch: \(label)") }
    }

    // A blank query is not a filter.
    check("empty query is inactive", !PickerSearch.isActive(""))
    check("whitespace query is inactive", !PickerSearch.isActive("  \n "))
    check("real query is active", PickerSearch.isActive("el"))
    check("empty query matches everything",
          PickerSearch.matches(query: "", label: "Anything"))

    // Label: substring, case-insensitive.
    check("label substring matches",
          PickerSearch.matches(query: "ree", label: "Greek"))
    check("label match ignores case",
          PickerSearch.matches(query: "GREEK", label: "Greek"))
    check("query is trimmed",
          PickerSearch.matches(query: "  greek  ", label: "Greek"))
    check("non-matching label is rejected",
          !PickerSearch.matches(query: "zzz", label: "Greek"))

    // searchLabel is the fully-qualified variant shown while searching.
    check("searchLabel is matched too",
          PickerSearch.matches(query: "greek", label: "F1 · Female",
                               searchLabel: "Greek · F1 · Female"))
    check("nil searchLabel is not matched against",
          !PickerSearch.matches(query: "greek", label: "F1 · Female"))

    // Keywords: prefix only. A substring rule would make "el" hit every code containing
    // those letters and bury the exact language.
    check("keyword prefix matches",
          PickerSearch.matches(query: "el", label: "Greek", keywords: ["el"]))
    check("keyword match is prefix-only, not substring",
          !PickerSearch.matches(query: "ue", label: "Cantonese", keywords: ["yue"]))
    check("empty keywords are ignored",
          !PickerSearch.matches(query: "a", label: "Greek", keywords: [""]))
    check("keyword match ignores case",
          PickerSearch.matches(query: "EL", label: "Greek", keywords: ["el"]))

    // STTLanguages.match must route through the same predicate, so the roster search and
    // the picker search cannot diverge.
    let all = STTLanguages.all
    check("match finds Greek by name", STTLanguages.match(all, query: "gree").contains { $0.code == "el" })
    check("match finds Greek by code", STTLanguages.match(all, query: "el").contains { $0.code == "el" })
    check("match is prefix-only on code",
          !STTLanguages.match(all, query: "ue").contains { $0.code == "yue" })
    check("match passes an empty query through",
          STTLanguages.match(all, query: "").count == all.count)

    return failures
}
