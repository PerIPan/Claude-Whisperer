import Foundation

/// Which coding agents are actually present on this machine.
///
/// First-run's agent pane needs this because the alternative is what the app did before:
/// `showHookInstructions(for: Platform.load())` one second after launch, where `load()`
/// falls back to `.claudeCode` when nothing is stored — which is precisely the first-run
/// state. Every new user got a wall of Claude Code JSON regardless of what they run.
///
/// Detection is by config directory, not by executable. These are CLI tools installed by
/// npm/brew/curl into wildly varying locations, so `InstalledApps` (which scans
/// `/Applications` for GUI bundles) cannot see them, and probing `$PATH` from an
/// `LSUIElement` app inherits a login shell's environment rather than the user's terminal.
/// A config directory means the agent has actually been run at least once, which is a
/// better signal for "should I offer this" than a binary existing somewhere.
///
/// Deliberately *advisory*: `FirstRunAgentPane` lists all four regardless, and detection
/// only decides ordering and the "found" label. A false negative must never hide an agent
/// the user has — it just means they scroll past one extra row.
enum AgentDetection {
    /// True when this agent's config directory exists — i.e. it has been run here.
    static func isPresent(_ platform: Platform) -> Bool {
        FileManager.default.fileExists(atPath: configDirectory(for: platform).path)
    }

    /// Present agents first (in `Platform.allCases` order), then the rest. Stable, so the
    /// list does not reshuffle between redraws.
    static func orderedByPresence() -> [Platform] {
        let all = Platform.allCases
        return all.filter(isPresent) + all.filter { !isPresent($0) }
    }

    static func presentPlatforms() -> [Platform] {
        Platform.allCases.filter(isPresent)
    }

    /// The directory whose existence means "this agent has run here". Derived from the
    /// same `Paths` entries `ConfigManager` writes to, so a path change cannot leave
    /// detection pointing at a stale location.
    private static func configDirectory(for platform: Platform) -> URL {
        switch platform {
        case .claudeCode:
            // ~/.claude — the settings file's parent. `~/.claude.json` is a sibling *file*
            // and would need its own check; the directory is created by any real use.
            return Paths.claudeSettings.deletingLastPathComponent()
        case .codexCLI:
            // ~/.codex
            return Paths.codexConfig.deletingLastPathComponent()
        case .pi:
            // ~/.pi/agent/extensions — deliberately the extensions dir rather than ~/.pi,
            // since that is what `applyToPi` writes into and what must exist for it to work.
            return Paths.piExtensionDest.deletingLastPathComponent()
        case .antigravity:
            // ~/.gemini/config
            return Paths.agyHooksConfig.deletingLastPathComponent()
        }
    }
}
