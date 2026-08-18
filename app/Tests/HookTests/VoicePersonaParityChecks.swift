import Foundation
import OpenWhispererKit

/// Cross-target parity: `VoicePersona.byPrefix` must match `resolve_flavor()`'s case arms
/// exactly — same prefixes, same accent, same persona name, same descriptor.
///
/// The failure this prevents is a disclosure that lies. Settings tells the user their voice
/// makes replies "dry and unflappable"; the hook is what actually tells the model. Reword one
/// and not the other and the app is now describing a personality it isn't applying — worse
/// than the silence it replaced, because it reads as informed consent.
///
/// Same arrangement as `VoiceLanguageParityChecks`: the hook stays the single source of
/// steering, the parser reads it rather than restating it, and this runner is the only one
/// that can see both sides.
func voicePersonaParityFailures() -> [String] {
    var failures: [String] = []

    let sharedPath = Hook.hooksDir.appendingPathComponent("voice-shared.sh")
    guard let shared = try? String(contentsOf: sharedPath, encoding: .utf8) else {
        return ["voice-shared.sh could not be read at \(sharedPath.path)"]
    }

    // Scope to resolve_flavor's body: `resolve_language_line()` below it also has `xx) …`
    // arms, and an unscoped match would blend the two maps together.
    guard let bodyStart = shared.range(of: "resolve_flavor() {") else {
        return ["voice-shared.sh: resolve_flavor() not found — did it get renamed?"]
    }
    let afterStart = shared[bodyStart.upperBound...]
    let body = afterStart.range(of: "\n}").map { String(afterStart[..<$0.lowerBound]) }
        ?? String(afterStart)

    // Arms look like:  a) accent="American English";  persona="American";  desc="…" ;;
    // Parsing the hook rather than restating it keeps this a parity check, not a third copy.
    var hookPersonas: [Character: VoicePersona.Persona] = [:]
    let pattern = #"\b([a-z])\)\s*accent="([^"]+)"\s*;\s*persona="([^"]+)"\s*;\s*desc="([^"]+)""#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(body.startIndex..., in: body)
    for match in regex.matches(in: body, range: range) {
        guard let prefixRange = Range(match.range(at: 1), in: body),
              let accentRange = Range(match.range(at: 2), in: body),
              let nameRange = Range(match.range(at: 3), in: body),
              let descRange = Range(match.range(at: 4), in: body),
              let prefix = String(body[prefixRange]).first else { continue }
        hookPersonas[prefix] = VoicePersona.Persona(
            accent: String(body[accentRange]),
            name: String(body[nameRange]),
            descriptor: String(body[descRange]))
    }

    if hookPersonas.isEmpty {
        return ["voice-shared.sh: resolve_flavor's case arms did not parse — did the map's shape change?"]
    }

    // Both directions: a prefix only in Swift is a disclosure for a persona the model never
    // gets, and one only in the hook is a persona applied with nothing said about it — the
    // very gap this type was added to close.
    for (prefix, hookPersona) in hookPersonas {
        guard let kitPersona = VoicePersona.byPrefix[prefix] else {
            failures.append("VoicePersona.byPrefix has no '\(prefix)' — the hook applies a \(hookPersona.name) persona that Settings never discloses")
            continue
        }
        if kitPersona.accent != hookPersona.accent {
            failures.append("accent mismatch for '\(prefix)': Kit says '\(kitPersona.accent)', hook says '\(hookPersona.accent)'")
        }
        if kitPersona.name != hookPersona.name {
            failures.append("persona name mismatch for '\(prefix)': Kit says '\(kitPersona.name)', hook says '\(hookPersona.name)'")
        }
        if kitPersona.descriptor != hookPersona.descriptor {
            failures.append("descriptor mismatch for '\(prefix)': Kit says '\(kitPersona.descriptor)', hook says '\(hookPersona.descriptor)'")
        }
    }
    for prefix in VoicePersona.byPrefix.keys where hookPersonas[prefix] == nil {
        failures.append("VoicePersona.byPrefix has '\(prefix)' but resolve_flavor() does not — Settings would disclose a persona the model is never given")
    }

    // The persona line is ungated and rides on every turn for a personified voice, so assert
    // the sentinel `HookTests` keys on elsewhere still surrounds it.
    if !body.contains("The voice speaking your reply has a") {
        failures.append("voice-shared.sh: resolve_flavor's persona sentinel changed — VoiceContextChecks keys on it")
    }

    return failures
}
