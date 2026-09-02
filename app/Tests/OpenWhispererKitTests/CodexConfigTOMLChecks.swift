import OpenWhispererKit

/// Checks for `CodexConfigTOML` — the migration that moves our Codex hook out of the inline
/// `[[hooks.UserPromptSubmit]]` tables in `~/.codex/config.toml` (Codex warns when a layer has
/// both `hooks.json` and inline `[hooks]`). Only our own tables may go: the `speak` MCP server,
/// `[features] hooks = true`, `[hooks.state]` trust hashes, and any foreign hook must survive.
func codexConfigTOMLFailures() -> [String] {
    var failures: [String] = []
    func expect(_ cond: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if !cond {
            let d = detail()
            failures.append("CodexConfigTOML.\(name)" + (d.isEmpty ? "" : ": \(d)"))
        }
    }

    let ourPath = "/Applications/OpenWhisperer.app/Contents/Resources/hooks/voice-context.sh"
    let inline = """
    [[hooks.UserPromptSubmit]]

    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "\(ourPath)"
    timeout = 30
    """

    // The shape a real install has after the pre-hooks.json app wrote it.
    let real = """
    model = "gpt-5.6-sol"

    [mcp_servers.OpenWhisperer]
    url = "http://localhost:8000/mcp"

    [mcp_servers.OpenWhisperer.tools.speak]
    approval_mode = "approve"

    \(inline)

    [hooks.state]

    [hooks.state."/Users/x/.codex/config.toml:user_prompt_submit:0:0"]
    trusted_hash = "sha256:7f2f"

    [features]
    hooks = true

    """
    let stripped = CodexConfigTOML.strippingOwnHooks(from: real)
    expect(!stripped.contains("voice-context.sh"), "stripRemovesOwnHook", stripped)
    expect(!stripped.contains("[[hooks.UserPromptSubmit]]"), "stripRemovesOwnGroupHeader", stripped)
    expect(stripped.contains("[mcp_servers.OpenWhisperer]\nurl = \"http://localhost:8000/mcp\""), "stripKeepsMCPServer", stripped)
    expect(stripped.contains("[mcp_servers.OpenWhisperer.tools.speak]\napproval_mode = \"approve\""), "stripKeepsMCPSubtable", stripped)
    expect(stripped.contains("[hooks.state]"), "stripKeepsHookState", stripped)
    expect(stripped.contains("trusted_hash = \"sha256:7f2f\""), "stripKeepsTrustedHash", stripped)
    expect(stripped.contains("[features]\nhooks = true"), "stripKeepsFeaturesFlag", stripped)
    expect(stripped.hasPrefix("model = \"gpt-5.6-sol\"\n"), "stripKeepsPreamble", stripped)
    expect(stripped.contains("approval_mode = \"approve\"\n\n[hooks.state]"), "stripLeavesSingleBlankLine", stripped.debugDescription)
    expect(CodexConfigTOML.strippingOwnHooks(from: stripped) == stripped, "stripIdempotent")
    expect(CodexConfigTOML.hasOwnInlineHook(real), "hasOwnInlineHookTrue")
    expect(!CodexConfigTOML.hasOwnInlineHook(stripped), "hasOwnInlineHookFalse")

    // A config without our hook comes back byte-identical, foreign UserPromptSubmit hook and all.
    let foreign = """
    model = "gpt-5.6-sol"

    [[hooks.UserPromptSubmit]]
    matcher = ".*"

    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "/Users/x/bin/lint-prompt.sh"

    [features]
    hooks = true
    """
    expect(CodexConfigTOML.strippingOwnHooks(from: foreign) == foreign, "stripNoOpOnForeign")
    expect(!CodexConfigTOML.hasOwnInlineHook(foreign), "hasOwnInlineHookFalseForeign")
    expect(CodexConfigTOML.strippingOwnHooks(from: "") == "", "stripNoOpOnEmpty")

    // Our group after a foreign one: only ours goes.
    let both = foreign + "\n\n" + inline + "\n"
    let bothStripped = CodexConfigTOML.strippingOwnHooks(from: both)
    expect(bothStripped.contains("lint-prompt.sh"), "stripKeepsForeignGroup", bothStripped)
    expect(bothStripped.contains("matcher = \".*\""), "stripKeepsForeignMatcher", bothStripped)
    expect(!bothStripped.contains("voice-context.sh"), "stripDropsOwnAmongForeign", bothStripped)
    expect(bothStripped.components(separatedBy: "[[hooks.UserPromptSubmit]]").count == 2, "stripLeavesOneGroupHeader", bothStripped)

    // Our hook sharing a group with a foreign one: the group header and the foreign hook stay.
    let sharedGroup = """
    [[hooks.UserPromptSubmit]]

    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "/Users/x/bin/lint-prompt.sh"

    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "\(ourPath)"
    timeout = 30
    """
    let sharedStripped = CodexConfigTOML.strippingOwnHooks(from: sharedGroup)
    expect(sharedStripped.contains("[[hooks.UserPromptSubmit]]"), "sharedGroupKeepsHeader", sharedStripped)
    expect(sharedStripped.contains("lint-prompt.sh"), "sharedGroupKeepsForeign", sharedStripped)
    expect(!sharedStripped.contains("voice-context.sh"), "sharedGroupDropsOurs", sharedStripped)

    // Headers with inner whitespace are still ours.
    let spaced = "[[ hooks.UserPromptSubmit ]]\n\n[[ hooks.UserPromptSubmit.hooks ]]\ntype = \"command\"\ncommand = \"\(ourPath)\"\n"
    expect(CodexConfigTOML.strippingOwnHooks(from: spaced) == "", "stripHandlesSpacedHeaders", CodexConfigTOML.strippingOwnHooks(from: spaced).debugDescription)

    // Legacy `notify = [...]` pointing at our old Stop-style hook goes; a foreign notify stays.
    let legacy = "notify = [\"/Applications/OpenWhisperer.app/Contents/Resources/hooks/codex-tts-hook.sh\"]\nnotify_on_error = true\n"
    expect(CodexConfigTOML.strippingOwnHooks(from: legacy) == "notify_on_error = true\n", "stripsLegacyNotify", CodexConfigTOML.strippingOwnHooks(from: legacy).debugDescription)
    let foreignNotify = "notify = [\"/usr/local/bin/ding\"]\n"
    expect(CodexConfigTOML.strippingOwnHooks(from: foreignNotify) == foreignNotify, "keepsForeignNotify")
    expect(!CodexConfigTOML.hasOwnInlineHook(legacy), "legacyNotifyIsNotAnInlineHook")

    return failures
}
