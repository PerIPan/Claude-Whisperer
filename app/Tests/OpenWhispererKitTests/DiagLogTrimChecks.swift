import Foundation
import OpenWhispererKit

/// Checks for `DiagLogTrim` — the size cap on the append-only `paste_debug.log`.
func diagLogTrimFailures() -> [String] {
    var failures: [String] = []
    func expect(_ condition: Bool, _ name: String, _ detail: String) {
        if !condition { failures.append("DiagLogTrim.\(name): \(detail)") }
    }
    func str(_ d: Data?) -> String? { d.map { String(decoding: $0, as: UTF8.self) } }

    // Under the cap (and exactly at it) is a no-op — the caller must not rewrite the file.
    expect(DiagLogTrim.trimmed(Data(), maxBytes: 100) == nil, "empty", "empty file trimmed")
    expect(DiagLogTrim.trimmed(Data(repeating: 0x61, count: 100), maxBytes: 100) == nil,
           "exactlyAtCap", "trimmed at exactly the cap")
    expect(DiagLogTrim.trimmed(Data(repeating: 0x61, count: 99), maxBytes: 100) == nil,
           "underCap", "trimmed under the cap")

    // Normal case: keeps whole trailing lines, dropping the partial one at the front.
    let lines = (1...40).map { "line\($0)" }.joined(separator: "\n") + "\n"
    let out = str(DiagLogTrim.trimmed(Data(lines.utf8), maxBytes: 100))
    expect(out != nil, "rotates", "nil for an over-cap log")
    if let out {
        expect(out.hasSuffix("line40\n"), "keepsNewest", "lost the newest line: \(out.suffix(20))")
        expect(!out.hasPrefix("\n"), "noLeadingNewline", "starts on a newline")
        expect(out.hasPrefix("line"), "wholeFirstLine", "first kept entry is a fragment: \(out.prefix(20))")
        expect(out.utf8.count <= 50, "halvesToBudget", "kept \(out.utf8.count) bytes, budget 50")
        expect(!out.contains("line1\n"), "dropsOldest", "kept the oldest line")
    }

    // The edge that used to truncate the file to zero bytes: the tail's only newline is its
    // last byte, so resuming after it would leave nothing. Keep the tail whole instead.
    let oneLine = Data((String(repeating: "x", count: 300) + "\n").utf8)
    let kept = DiagLogTrim.trimmed(oneLine, maxBytes: 100)
    expect(kept != nil, "singleLineRotates", "nil for an over-cap single line")
    expect((kept?.count ?? 0) > 0, "neverEmpties", "truncated the log to 0 bytes")

    // No newline anywhere in the tail — same rule, never empty.
    let noNewline = Data(String(repeating: "y", count: 300).utf8)
    expect((DiagLogTrim.trimmed(noNewline, maxBytes: 100)?.count ?? 0) > 0,
           "noNewlineNeverEmpties", "truncated a newline-free log to 0 bytes")

    // Degenerate budget must not trap.
    expect(DiagLogTrim.trimmed(Data(repeating: 0x61, count: 10), maxBytes: 0) == nil,
           "zeroBudget", "acted on a zero budget")

    return failures
}
