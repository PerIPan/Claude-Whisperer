import Foundation
import OpenWhispererKit

/// Cross-target parity: `VoicePersona.byPrefix` must match `resolve_flavor()`'s case arms
/// exactly — same keys, same accent, same persona name, same descriptor.
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
    // arms, and an unscoped match would blend the two maps together. Parsing the hook rather
    // than restating it keeps this a parity check, not a third copy (`VoiceSharedMaps` is the
    // one parser, shared with the Pi mirror's check).
    guard let body = VoiceSharedMaps.body(of: "resolve_flavor", in: shared) else {
        return ["voice-shared.sh: resolve_flavor() not found — did it get renamed?"]
    }
    let hookPersonas = VoiceSharedMaps.personas(inFlavorBody: body)

    if hookPersonas.isEmpty {
        return ["voice-shared.sh: resolve_flavor's case arms did not parse — did the map's shape change?"]
    }

    func compare(_ key: String, _ kit: VoicePersona.Persona) {
        guard let hook = hookPersonas[key] else {
            failures.append("resolve_flavor() has no '\(key)' arm — Settings offers the \(kit.name) persona but the model would never be given it")
            return
        }
        if kit.accent != hook.accent {
            failures.append("accent mismatch for '\(key)': Kit says '\(kit.accent)', hook says '\(hook.accent)'")
        }
        if kit.name != hook.name {
            failures.append("persona name mismatch for '\(key)': Kit says '\(kit.name)', hook says '\(hook.name)'")
        }
        if kit.descriptor != hook.descriptor {
            failures.append("descriptor mismatch for '\(key)': Kit says '\(kit.descriptor)', hook says '\(hook.descriptor)'")
        }
    }

    // Every persona must be reachable by id (the override path) and, when it has one, by
    // its Kokoro prefix (the automatic path). Both are real lookups the hook performs.
    var expected = Set<String>()
    for kit in VoicePersona.all {
        compare(kit.id, kit)
        expected.insert(kit.id)
        if let prefix = kit.prefix {
            compare(String(prefix), kit)
            expected.insert(String(prefix))
        }
    }

    // And nothing the hook knows may be missing from the Kit — that is a persona applied
    // with nothing said about it, the gap VoicePersona exists to close.
    for key in hookPersonas.keys where !expected.contains(key) {
        failures.append("resolve_flavor() has a '\(key)' arm that VoicePersona.all does not — Settings would never disclose or offer it")
    }

    // The persona line is ungated and rides on every turn for a personified voice, so assert
    // the sentinel `HookTests` keys on elsewhere still surrounds it.
    if !body.contains("The voice speaking your reply has") {
        failures.append("voice-shared.sh: resolve_flavor's persona sentinel changed — VoiceContextChecks keys on it")
    }

    return failures
}
