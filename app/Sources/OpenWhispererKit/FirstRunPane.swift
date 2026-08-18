import Foundation

/// The four steps of first-run setup, in order.
///
/// Pure so the ordering and the "can I leave this pane" rule are testable under CLT — the
/// views themselves are AppKit-bound and are not. Keeping navigation here also means the
/// sheet has exactly one definition of what "next" means, rather than four views each
/// deciding for themselves.
public enum FirstRunPane: Int, CaseIterable, Sendable {
    case permissions
    case dictate
    case voice
    case agent

    public var title: String {
        switch self {
        case .permissions: return "Permissions"
        case .dictate: return "Dictate"
        case .voice: return "Voice"
        case .agent: return "Agent"
        }
    }

    /// One line under the title. Says what the pane is for, not what to do — the controls
    /// say that.
    public var subtitle: String {
        switch self {
        case .permissions:
            return "Open Whisperer needs two macOS grants before it can hear you or type for you."
        case .dictate:
            return "How you start dictation, and what language you speak."
        case .voice:
            return "The voice that reads replies aloud, and the character it carries."
        case .agent:
            return "Connect a coding agent so its replies are spoken."
        }
    }

    public var next: FirstRunPane? { FirstRunPane(rawValue: rawValue + 1) }
    public var previous: FirstRunPane? { FirstRunPane(rawValue: rawValue - 1) }
    public var isLast: Bool { next == nil }
    public var isFirst: Bool { previous == nil }

    /// 1-based position, for "Step 2 of 4".
    public var step: Int { rawValue + 1 }
    public static var count: Int { allCases.count }

    /// Nothing blocks. Permissions are the only pane that gates anything real, and even it
    /// lets you pass: a user who wants to grant later should not be trapped in a modal, and
    /// the Settings → General permission list is the durable home for that state anyway.
    ///
    /// This exists as a named rule rather than an implicit `true` so that a future pane
    /// which *does* need to block has somewhere to say so.
    public var blocksAdvance: Bool { false }
}
