import Foundation
import OpenWhispererKit

/// Static option tables shared by the Settings tabs (moved verbatim from MenuBarView
/// so Dictation/Voice don't each keep their own copy).
enum SettingsData {
    /// Full Kokoro-82M v1.0 roster, grouped by language for the nested-submenu picker.
    /// Non-default voices download on first selection via `KokoroTTS.ensureVoicePack`.
    static let voiceGroups: [(group: String, options: [(id: String, label: String)])] = {
        TTSVoiceRegistry.groups.map { group in
            (group.name, group.voices.map { ($0.id, "\($0.name) (\($0.gender.prefix(1)))") })
        }
    }()

    static let allVoices: [(id: String, label: String)] = {
        TTSVoiceRegistry.allVoices.map { ($0.id, "\($0.name) (\($0.gender.prefix(1)))") }
    }()

    static let languages: [(id: String, label: String)] = [
        ("auto", "Auto-detect"), ("en", "English"), ("es", "Spanish"), ("fr", "French"),
        ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"),
        ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("ar", "Arabic"),
        ("hi", "Hindi"), ("ru", "Russian"), ("pl", "Polish"), ("tr", "Turkish"),
        ("uk", "Ukrainian"), ("sv", "Swedish"),
    ]

    /// Spoken-summary length. "full" folded into the richest tier (AGENTS.md), so the
    /// picker offers three — the stray fourth entry the pop-over still listed is gone.
    static let styleLevels: [(id: String, label: String)] = [
        ("terse", "Terse"), ("normal", "Normal"), ("rich", "Rich"),
    ]

    /// When replies are spoken; values match what `voice-context.sh` reads.
    /// Labels are self-describing so no explanatory caption is needed.
    static let responseModes: [(id: String, label: String)] = [
        ("voice", "Only when I dictate"), ("always", "On every turn"),
    ]

    static let focusApps: [(id: String, label: String)] = [
        ("Code", "VS Code"), ("Code - Insiders", "VS Code Insiders"),
        ("Cursor", "Cursor (AI Editor)"), ("Windsurf", "Windsurf (AI Editor)"),
        ("Zed", "Zed (Editor)"), ("Xcode", "Xcode (Apple IDE)"),
        ("Sublime Text", "Sublime Text (Editor)"), ("Nova", "Nova (Panic)"),
        ("Fleet", "Fleet (JetBrains)"), ("Claude", "Claude (Desktop)"),
        ("Terminal", "Terminal (macOS)"), ("iTerm2", "iTerm2 (Terminal)"),
        ("Warp", "Warp (Terminal)"), ("Alacritty", "Alacritty (Terminal)"),
        ("Ghostty", "Ghostty (Terminal)"), ("CUSTOM", "Custom…"),
    ]

    /// "1×", "1.15×" — trims trailing zeros so slider readouts stay tidy.
    static func multiplierLabel(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s + "×"
    }
}
