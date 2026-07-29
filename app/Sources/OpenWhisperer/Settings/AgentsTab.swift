import SwiftUI

/// Which coding agent gets voice, and whether its hook/extension is wired up.
struct AgentsTab: View {
    @State private var selectedPlatform: Platform = .claudeCode
    @State private var hookApplied = false
    @State private var applyMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OWCard {
                VStack(alignment: .leading, spacing: 10) {
                    OWCardHeader(title: "Set up voice for", icon: "hammer",
                                 help: "Wire up spoken replies for your CLI (Claude Code, Codex, Antigravity, or Pi) — Auto-Apply writes the hooks.")

                    OWPickerRow(label: "Agent", labelWidth: 62) {
                        OWMenuPicker(selection: $selectedPlatform,
                                     options: Platform.allCases.map { (id: $0, label: $0.label) })
                            .frame(maxWidth: .infinity)
                            .help("Which coding agent you're setting up. Claude/Codex/Antigravity get a hook + speak tool; Pi gets an extension.")
                    }
                    .onChange(of: selectedPlatform) { _, newValue in
                        newValue.save()
                        refreshHookState()
                    }

                    OWInternalDivider()

                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Hook").font(OWFont.body(11))
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 80, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { ConfigManager.showHookInstructions(for: selectedPlatform) }
                        .help("How it works — opens the per-platform explainer and the manual setup snippet.")

                        Button(action: {
                            let result = ConfigManager.applyHook(for: selectedPlatform)
                            hookApplied = result.success
                            applyMessage = result.message
                            refreshHookState()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { applyMessage = "" }
                        }) {
                            Label(hookApplied ? "Applied" : "Auto-Apply",
                                  systemImage: hookApplied ? "checkmark.circle.fill" : "bolt.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OWRowButtonStyle(tinted: hookApplied, urgent: !hookApplied))
                        .help(helpText)
                    }

                    if !applyMessage.isEmpty {
                        Text(applyMessage)
                            .font(OWFont.caption())
                            .foregroundColor(applyMessage.lowercased().contains("fail")
                                             ? OWColor.danger : OWColor.live)
                            .transition(.opacity)
                    }
                }
            }
        }
        .onAppear {
            selectedPlatform = Platform.load()
            refreshHookState()
        }
    }

    private var helpText: String {
        switch selectedPlatform {
        case .claudeCode:
            return "Writes the UserPromptSubmit hook into ~/.claude/settings.json + the speak MCP server into ~/.claude.json. Re-applies cleanly on rebuild."
        case .codexCLI:
            return "Writes the speak MCP server + UserPromptSubmit hook into ~/.codex/config.toml (needs one-time hook trust). Re-applies cleanly on rebuild."
        case .pi:
            return "Copies the OpenWhisperer extension into ~/.pi/agent/extensions/ (no MCP). Run /reload in Pi afterward."
        default:
            return "Writes the speak MCP server into ~/.gemini/config/mcp_config.json + the PreInvocation hook into ~/.gemini/config/hooks.json. Start a new agy session afterward."
        }
    }

    private func refreshHookState() {
        hookApplied = ConfigManager.checkHookConfigured(for: selectedPlatform)
    }
}
