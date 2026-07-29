import Foundation

/// The five Settings tabs, in display order.
///
/// Homing rationale (2026-07-20 design): "Input" is named **Dictation** so it never
/// collides with **Voice** (spoken replies) — mic-in vs speaker-out. The overlay control
/// lives in Dictation as ONE control (OFF/Wave/LED Bars/Graph/Curtain); the previously
/// shipped native tabs wrongly split its on/off from its style across two tabs.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, dictation, voice, agents, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:   return "General"
        case .dictation: return "Dictation"
        case .voice:     return "Voice"
        case .agents:    return "Agents"
        case .advanced:  return "Advanced"
        }
    }

    /// SF Symbol shown above the label in the branded tab bar.
    var icon: String {
        switch self {
        case .general:   return "gearshape"
        case .dictation: return "mic"
        case .voice:     return "speaker.wave.2"
        case .agents:    return "wand.and.stars"
        case .advanced:  return "wrench.and.screwdriver"
        }
    }
}
