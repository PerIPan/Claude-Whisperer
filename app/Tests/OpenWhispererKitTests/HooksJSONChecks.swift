import Foundation
import OpenWhispererKit

/// Checks for `HooksJSON` — the hooks-file merge shared by Claude Code's settings.json and
/// Codex's hooks.json. Both carry the same `{"hooks": {Event: [{"hooks": [...]}]}}` shape, and
/// both files are shared with other tools (Herdr writes a SessionStart entry into Codex's), so
/// every edit must touch only our own entries.
func hooksJSONFailures() -> [String] {
    var failures: [String] = []
    func expect(_ cond: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if !cond {
            let d = detail()
            failures.append("HooksJSON.\(name)" + (d.isEmpty ? "" : ": \(d)"))
        }
    }

    let ourPath = "/Applications/OpenWhisperer.app/Contents/Resources/hooks/voice-context.sh"
    let herdrPath = "bash '/Users/x/.codex/herdr-agent-state.sh' session"
    let ours: [String: Any] = ["type": "command", "command": ourPath, "timeout": 30]
    let herdr: [String: Any] = ["type": "command", "command": herdrPath, "timeout": 10]

    func groups(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        ((root["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
    }
    func commands(_ root: [String: Any], _ event: String) -> [String] {
        groups(root, event)
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
    }
    func same(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        NSDictionary(dictionary: a).isEqual(to: b)
    }

    // Empty document → one group holding our hook, fields intact.
    let fresh = HooksJSON.upsertingOwnHook(in: [:], event: "UserPromptSubmit", hook: ours)
    expect(commands(fresh, "UserPromptSubmit") == [ourPath], "upsertIntoEmpty", "got \(fresh)")
    let freshHook = (groups(fresh, "UserPromptSubmit").first?["hooks"] as? [[String: Any]])?.first ?? [:]
    expect(freshHook["timeout"] as? Int == 30 && freshHook["type"] as? String == "command", "upsertKeepsHookFields", "got \(freshHook)")

    // Entries under other events survive untouched (Herdr's SessionStart).
    let withHerdr: [String: Any] = ["hooks": ["SessionStart": [["hooks": [herdr]]]]]
    let merged = HooksJSON.upsertingOwnHook(in: withHerdr, event: "UserPromptSubmit", hook: ours)
    expect(commands(merged, "SessionStart") == [herdrPath], "upsertKeepsOtherEvents")
    expect(commands(merged, "UserPromptSubmit") == [ourPath], "upsertAddsAlongsideOtherEvents")

    // Foreign groups under the same event survive; ours is appended after them.
    let sharedEvent: [String: Any] = ["hooks": ["UserPromptSubmit": [["hooks": [herdr]]]]]
    let shared = HooksJSON.upsertingOwnHook(in: sharedEvent, event: "UserPromptSubmit", hook: ours)
    expect(commands(shared, "UserPromptSubmit") == [herdrPath, ourPath], "upsertKeepsForeignSameEvent", "got \(commands(shared, "UserPromptSubmit"))")

    // A stale entry of ours (old bundle path) is replaced, not duplicated.
    let stale: [String: Any] = ["type": "command", "command": "/Users/x/old/OpenWhisperer.app/Contents/Resources/hooks/voice-context.sh"]
    let withStale: [String: Any] = ["hooks": ["UserPromptSubmit": [["hooks": [stale]]]]]
    let replaced = HooksJSON.upsertingOwnHook(in: withStale, event: "UserPromptSubmit", hook: ours)
    expect(commands(replaced, "UserPromptSubmit") == [ourPath], "upsertReplacesStale", "got \(commands(replaced, "UserPromptSubmit"))")

    // Idempotent: applying twice yields the same document.
    let twice = HooksJSON.upsertingOwnHook(in: merged, event: "UserPromptSubmit", hook: ours)
    expect(same(twice, merged), "upsertIdempotent", "got \(twice)")

    // Unrelated top-level keys survive (settings.json carries far more than hooks).
    let withOther: [String: Any] = ["model": "opus", "hooks": ["SessionStart": [["hooks": [herdr]]]]]
    let mergedOther = HooksJSON.upsertingOwnHook(in: withOther, event: "UserPromptSubmit", hook: ours)
    expect(mergedOther["model"] as? String == "opus", "upsertKeepsTopLevelKeys")

    // Removal: only ours goes; a foreign hook sharing our group stays; an emptied event is dropped.
    let mixedGroup: [String: Any] = ["hooks": [
        "UserPromptSubmit": [["hooks": [herdr, ours]]],
        "Stop": [["hooks": [ours]]],
    ]]
    let removed = HooksJSON.removingOwnHooks(from: mixedGroup, event: "UserPromptSubmit")
    expect(commands(removed, "UserPromptSubmit") == [herdrPath], "removeKeepsForeignInGroup", "got \(commands(removed, "UserPromptSubmit"))")
    expect(commands(removed, "Stop") == [ourPath], "removeTouchesOnlyGivenEvent")
    let emptied = HooksJSON.removingOwnHooks(from: removed, event: "Stop")
    expect((emptied["hooks"] as? [String: Any])?["Stop"] == nil, "removeDropsEmptiedEvent", "got \(emptied)")
    expect(same(HooksJSON.removingOwnHooks(from: emptied, event: "Stop"), emptied), "removeIdempotent")
    expect(same(HooksJSON.removingOwnHooks(from: withHerdr, event: "UserPromptSubmit"), withHerdr), "removeNoOpWhenAbsent")

    // Presence check.
    expect(HooksJSON.containsOwnHook(merged, event: "UserPromptSubmit"), "containsTrue")
    expect(!HooksJSON.containsOwnHook(withHerdr, event: "UserPromptSubmit"), "containsFalseForeignOnly")
    expect(!HooksJSON.containsOwnHook([:], event: "UserPromptSubmit"), "containsFalseEmpty")

    // Every historical spelling of our hook counts as ours.
    for legacy in ["/x/tts-hook.sh", "/x/Open Whisperer.app/h.sh", "/x/mlx-openai-whisper/h.sh"] {
        expect(HooksJSON.isOwnHook(legacy), "isOwnHookLegacy", legacy)
    }
    expect(!HooksJSON.isOwnHook(herdrPath), "isOwnHookForeign")

    // Rendering: 2-space indent, sorted keys, unescaped slashes — the house style of both files.
    let rendered = HooksJSON.render(fresh) ?? ""
    let expectedBody = """
    {
      "hooks": {
        "UserPromptSubmit": [
          {
            "hooks": [
              {
                "command": "\(ourPath)",
                "timeout": 30,
                "type": "command"
              }
            ]
          }
        ]
      }
    }
    """
    expect(rendered == expectedBody, "renderHouseStyle", "got \(rendered.debugDescription)")

    return failures
}
