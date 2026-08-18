import Foundation
import OpenWhispererKit

/// Guards first-run navigation: the order, the ends, and the no-trap rule.
func firstRunPaneFailures() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool) {
        if !ok { failures.append("FirstRunPane: \(label)") }
    }

    check("has four panes", FirstRunPane.count == 4)
    check("permissions is first", FirstRunPane.allCases.first == .permissions)
    check("agent is last", FirstRunPane.allCases.last == .agent)
    check("permissions reports first", FirstRunPane.permissions.isFirst)
    check("agent reports last", FirstRunPane.agent.isLast)
    check("permissions has no previous", FirstRunPane.permissions.previous == nil)
    check("agent has no next", FirstRunPane.agent.next == nil)

    // Walking next from the first pane must reach the last and visit every pane once —
    // a gap here would strand the user mid-setup with no way forward.
    var seen: [FirstRunPane] = []
    var cursor: FirstRunPane? = .permissions
    while let pane = cursor {
        seen.append(pane)
        cursor = pane.next
        if seen.count > FirstRunPane.count { break }
    }
    check("next walks every pane once", seen == FirstRunPane.allCases)

    // And back again, so Back is never a dead end.
    var backwards: [FirstRunPane] = []
    var reverse: FirstRunPane? = .agent
    while let pane = reverse {
        backwards.append(pane)
        reverse = pane.previous
        if backwards.count > FirstRunPane.count { break }
    }
    check("previous walks every pane once", backwards == FirstRunPane.allCases.reversed())

    // Step numbering is 1-based and contiguous, since it renders as "Step 2 of 4".
    check("steps are 1...4", FirstRunPane.allCases.map(\.step) == [1, 2, 3, 4])

    // The no-trap rule. If a pane ever gates, that is a deliberate product decision and
    // this check should be updated with it — not silently flipped.
    for pane in FirstRunPane.allCases {
        check("\(pane.title) does not block advancing", !pane.blocksAdvance)
    }

    // Copy sanity: every pane needs both, and an empty string renders as a blank row.
    for pane in FirstRunPane.allCases {
        check("\(pane.title) has a title", !pane.title.isEmpty)
        check("\(pane.title) has a subtitle", !pane.subtitle.isEmpty)
    }

    return failures
}
