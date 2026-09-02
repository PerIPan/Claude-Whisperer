import Foundation

/// Parsers for the two maps in `hooks/voice-shared.sh` that other targets mirror: the persona
/// arms of `resolve_flavor()` and the code→language arms of `resolve_language_line()`, plus
/// their TypeScript twins in `pi/openwhisperer.ts`. The hook stays the source of truth; the
/// parity checks read it rather than restating it, so there is no third copy to drift.
enum VoiceSharedMaps {
    struct Persona: Equatable {
        let accent: String
        let name: String
        let descriptor: String
    }

    /// The text between `name() {` and the first line that is just `}`. Scoping matters:
    /// both bash functions are `case` statements whose arms would otherwise blend.
    static func body(of function: String, in script: String) -> String? {
        guard let start = script.range(of: "\(function)() {") else { return nil }
        let after = script[start.upperBound...]
        return after.range(of: "\n}").map { String(after[..<$0.lowerBound]) } ?? String(after)
    }

    /// Bash arms:  `a|american) accent="…"; persona="…"; desc="…" ;;`  → one entry per key.
    /// The label allows `|` alternates and words, not just a single character: personas are
    /// reachable by id as well as by voice prefix.
    static func personas(inFlavorBody body: String) -> [String: Persona] {
        var out: [String: Persona] = [:]
        let pattern = #"(?:^|[\s;])([a-z]{1,12}(?:\|[a-z]{1,12})*)\)\s*accent="([^"]+)"\s*;\s*persona="([^"]+)"\s*;\s*desc="([^"]+)""#
        let regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        for m in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let keys = Range(m.range(at: 1), in: body),
                  let accent = Range(m.range(at: 2), in: body),
                  let name = Range(m.range(at: 3), in: body),
                  let desc = Range(m.range(at: 4), in: body) else { continue }
            let persona = Persona(accent: String(body[accent]), name: String(body[name]), descriptor: String(body[desc]))
            for key in body[keys].split(separator: "|") { out[String(key)] = persona }
        }
        return out
    }

    /// Bash arms:  `nl) language="Dutch" ;;`  → code → name. `{2,3}` not `{2}`: a three-letter
    /// code like `yue` would otherwise register as `ue` and compare against the wrong language.
    static func languages(inLanguageBody body: String) -> [String: String] {
        var out: [String: String] = [:]
        let regex = try! NSRegularExpression(pattern: #"\b([a-z]{2,3})\)\s*language="([^"]+)""#)
        for m in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let code = Range(m.range(at: 1), in: body),
                  let name = Range(m.range(at: 2), in: body) else { continue }
            out[String(body[code])] = String(body[name])
        }
        return out
    }

    /// TypeScript entries:  `{ keys: ["a", "american"], accent: "…", persona: "…", desc: "…" }`.
    static func personas(inTypeScript ts: String) -> [String: Persona] {
        var out: [String: Persona] = [:]
        let pattern = #"keys:\s*\[([^\]]+)\]\s*,\s*accent:\s*"([^"]+)"\s*,\s*persona:\s*"([^"]+)"\s*,\s*desc:\s*"([^"]+)""#
        let regex = try! NSRegularExpression(pattern: pattern)
        for m in regex.matches(in: ts, range: NSRange(ts.startIndex..., in: ts)) {
            guard let keys = Range(m.range(at: 1), in: ts),
                  let accent = Range(m.range(at: 2), in: ts),
                  let name = Range(m.range(at: 3), in: ts),
                  let desc = Range(m.range(at: 4), in: ts) else { continue }
            let persona = Persona(accent: String(ts[accent]), name: String(ts[name]), descriptor: String(ts[desc]))
            for raw in ts[keys].split(separator: ",") {
                let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !key.isEmpty { out[key] = persona }
            }
        }
        return out
    }

    /// TypeScript map:  `const LANGUAGES … = { nl: "Dutch", … };`  → code → name, scoped to that
    /// object literal so an unrelated `xx: "…"` elsewhere in the file is not absorbed.
    static func languages(inTypeScript ts: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let start = ts.range(of: "const LANGUAGES") else { return out }
        let after = ts[start.upperBound...]
        guard let open = after.firstIndex(of: "{"), let close = after[open...].firstIndex(of: "}") else { return out }
        let body = String(after[open...close])
        let regex = try! NSRegularExpression(pattern: #"\b([a-z]{2,3}):\s*"([^"]+)""#)
        for m in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let code = Range(m.range(at: 1), in: body),
                  let name = Range(m.range(at: 2), in: body) else { continue }
            out[String(body[code])] = String(body[name])
        }
        return out
    }
}
