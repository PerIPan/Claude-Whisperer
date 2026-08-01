import Foundation

/// The find-as-you-type predicate behind `OWSearchablePicker`.
///
/// Pure and in Kit so the search the UI actually runs is the search that is unit-tested.
/// An earlier cut had the rule written twice — once in a `STTLanguages.match` convenience
/// no caller reached, once inline in the picker — so the tested version and the shipped
/// version were different code. Both reviewers caught it; this is now the one definition,
/// and the unreachable convenience is gone.
public enum PickerSearch {
    /// Whether a query should filter at all. A blank query is not a filter.
    public static func isActive(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Case-insensitive: substring on either label, **prefix** on any keyword.
    ///
    /// Keywords are ISO codes, and prefix-matching them is the point — a substring rule
    /// would make the two-letter query "el" match every code containing those letters and
    /// bury the exact hit (Greek) in noise.
    public static func matches(
        query: String, label: String, searchLabel: String? = nil, keywords: [String] = []
    ) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if label.lowercased().contains(q) { return true }
        if let searchLabel, searchLabel.lowercased().contains(q) { return true }
        return keywords.contains { !$0.isEmpty && $0.lowercased().hasPrefix(q) }
    }
}
