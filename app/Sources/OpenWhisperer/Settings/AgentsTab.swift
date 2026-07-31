import SwiftUI

/// Which coding agents can speak. All four are listed with their own status and
/// Connect button — you can run several agents, so a single-select picker misled.
struct AgentsTab: View {
    /// Connection state per platform, refreshed on appear and after each connect.
    @State private var connected: [Platform: Bool] = [:]
    /// Result of the most recent connect, kept until the next one (failures must not
    /// vanish on a timer).
    @State private var lastResult: (platform: Platform, ok: Bool, message: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OWCard {
                VStack(alignment: .leading, spacing: 10) {
                    OWCardHeader(title: "Coding agents", icon: "wand.and.stars",
                                 help: "Connect an agent so its replies are spoken aloud. Connecting writes that agent's hook and speak tool; you can connect as many as you use.")

                    ForEach(Array(Platform.allCases.enumerated()), id: \.element) { index, platform in
                        if index > 0 { OWInternalDivider() }
                        agentRow(platform)
                    }
                }
            }

            if let result = lastResult {
                OWCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(result.ok ? OWColor.live : OWColor.danger)
                            Text(result.message)
                                .font(OWFont.body(11))
                                .foregroundColor(OWColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // The post-connect step is a hard blocker, so it stays on screen
                        // instead of living in a tooltip.
                        if result.ok, let step = nextStep(for: result.platform) {
                            Text(step)
                                .font(OWFont.caption())
                                .foregroundColor(OWColor.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .onAppear(perform: refreshAll)
    }

    private func agentRow(_ platform: Platform) -> some View {
        let isConnected = connected[platform] ?? false
        return HStack(spacing: 8) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundColor(isConnected ? OWColor.live : OWColor.inkFaint)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(platform.label)
                        .font(OWFont.body(12))
                        .foregroundColor(OWColor.ink)
                    // Visible ⓘ: spells out exactly which files connecting touches.
                    OWInfoTip(text: connectHelp(for: platform))
                    // Setup instructions live next to the agent they describe, not beside the
                    // Connect button where a text link competed with the row's primary action.
                    Button { ConfigManager.showHookInstructions(for: platform) } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundColor(OWColor.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .help("How it works")
                    .accessibilityLabel("How \(platform.label) works")
                }
                Text(isConnected ? "Connected" : "Not connected")
                    .font(OWFont.caption())
                    .foregroundColor(isConnected ? OWColor.inkSoft : OWColor.inkFaint)
            }

            Spacer(minLength: 6)

            Button(isConnected ? "Reconnect" : "Connect") { connect(platform) }
                .buttonStyle(OWRowButtonStyle(tinted: isConnected, urgent: !isConnected))
                .frame(width: 92)
        }
    }

    private func connect(_ platform: Platform) {
        let result = ConfigManager.applyHook(for: platform)
        lastResult = (platform, result.success, result.message)
        // Keep `selected_platform` pointing at the most recently connected agent —
        // it's what first-run instructions default to.
        if result.success { platform.save() }
        refreshAll()
    }

    private func refreshAll() {
        var next: [Platform: Bool] = [:]
        for platform in Platform.allCases {
            next[platform] = ConfigManager.checkHookConfigured(for: platform)
        }
        connected = next
    }

    /// The manual step each agent needs after being connected.
    private func nextStep(for platform: Platform) -> String? {
        switch platform {
        case .claudeCode:
            return "Start a new Claude Code session to pick up the hook."
        case .codexCLI:
            return "Codex skips untrusted hooks — approve the Open Whisperer hook once when Codex prompts you."
        case .pi:
            return "Run /reload in Pi to load the extension."
        case .antigravity:
            return "Start a new agy session to pick up the hook."
        }
    }

    private func connectHelp(for platform: Platform) -> String {
        switch platform {
        case .claudeCode:
            return "Writes the UserPromptSubmit hook into ~/.claude/settings.json and the speak MCP server into ~/.claude.json. Re-applies cleanly on rebuild."
        case .codexCLI:
            return "Writes the speak MCP server and UserPromptSubmit hook into ~/.codex/config.toml. Re-applies cleanly on rebuild."
        case .pi:
            return "Copies the Open Whisperer extension into ~/.pi/agent/extensions/ (Pi is MCP-free)."
        case .antigravity:
            return "Writes the speak MCP server into ~/.gemini/config/mcp_config.json and the PreInvocation hook into ~/.gemini/config/hooks.json."
        }
    }
}
