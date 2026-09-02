import Foundation

/// The `{"hooks": {Event: [{"matcher"?: …, "hooks": [{"type", "command", …}]}]}}` document that
/// Claude Code's `~/.claude/settings.json` and Codex's `~/.codex/hooks.json` both use for
/// lifecycle hooks. Both files are shared with other tools (Herdr keeps a SessionStart entry in
/// Codex's), so every edit here is scoped to our own entries: foreign events, foreign groups,
/// and foreign hooks inside a group we share all come through untouched. Pure Foundation so the
/// merge is unit-testable under Command Line Tools.
public enum HooksJSON {
    /// Substrings that identify any Open Whisperer hook command, across every name the hook has
    /// had. `CodexConfigTOML` uses the same list to recognise our inline tables.
    public static let ownHookMarkers = [
        "tts-hook.sh",
        "voice-context.sh",
        "Open Whisperer",
        "OpenWhisperer",
        "mlx-openai-whisper",
    ]

    public static func isOwnHook(_ command: String) -> Bool {
        ownHookMarkers.contains { command.contains($0) }
    }

    private static func isOwnEntry(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String).map(isOwnHook) ?? false
    }

    /// Drop our hooks under `event`. A group that held only ours goes with them; a group we
    /// share keeps its other hooks; an event left with no groups is removed from `hooks`.
    public static func removingOwnHooks(from root: [String: Any], event: String) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return root }
        let kept: [[String: Any]] = groups.compactMap { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return group }
            let foreign = inner.filter { !isOwnEntry($0) }
            if foreign.count == inner.count { return group }
            if foreign.isEmpty { return nil }
            var trimmed = group
            trimmed["hooks"] = foreign
            return trimmed
        }
        if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        root["hooks"] = hooks
        return root
    }

    /// Register `hook` under `event` in a group of its own, replacing any earlier entry of ours
    /// (a stale bundle path, an older hook name). Idempotent.
    public static func upsertingOwnHook(in root: [String: Any], event: String, hook: [String: Any]) -> [String: Any] {
        var root = removingOwnHooks(from: root, event: event)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var groups = hooks[event] as? [[String: Any]] ?? []
        groups.append(["hooks": [hook]])
        hooks[event] = groups
        root["hooks"] = hooks
        return root
    }

    public static func containsOwnHook(_ root: [String: Any], event: String) -> Bool {
        guard let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] else { return false }
        return groups.contains { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).contains(where: isOwnEntry)
        }
    }

    /// Serialise in the style both files use: 2-space indent, `"key": value`, sorted keys,
    /// unescaped slashes. Foundation's `.prettyPrinted` writes `"key" : value` on Darwin and
    /// differs across platforms, so the structure is laid out here and only the leaves (strings,
    /// numbers, booleans, null) are handed to `JSONSerialization` for escaping.
    public static func render(_ root: [String: Any]) -> String? {
        var out = ""
        do { try write(root, indent: 0, into: &out) } catch { return nil }
        return out
    }

    private struct Unrenderable: Error {}

    private static func write(_ value: Any, indent: Int, into out: inout String) throws {
        let pad = String(repeating: " ", count: indent)
        let inner = pad + "  "
        if let dict = value as? [String: Any] {
            guard !dict.isEmpty else { out += "{}"; return }
            let keys = dict.keys.sorted()
            out += "{\n"
            for (i, key) in keys.enumerated() {
                out += inner
                try write(key, indent: 0, into: &out)
                out += ": "
                try write(dict[key]!, indent: indent + 2, into: &out)
                out += i + 1 < keys.count ? ",\n" : "\n"
            }
            out += pad + "}"
        } else if let array = value as? [Any] {
            guard !array.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (i, item) in array.enumerated() {
                out += inner
                try write(item, indent: indent + 2, into: &out)
                out += i + 1 < array.count ? ",\n" : "\n"
            }
            out += pad + "]"
        } else {
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
                  let leaf = String(data: data, encoding: .utf8) else { throw Unrenderable() }
            out += leaf
        }
    }
}
