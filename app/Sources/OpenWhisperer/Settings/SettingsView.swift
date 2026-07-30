import SwiftUI

/// Root of the branded Settings window: our own tab bar over the selected tab's body.
/// Fixed width; each tab reports its own height and the hosting window resizes to fit.
struct SettingsView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var setupManager: SetupManager
    @EnvironmentObject var dictationManager: DictationManager
    @EnvironmentObject var accessibilityManager: AccessibilityManager

    /// Fixed content width (the window is not user-resizable).
    static let contentWidth: CGFloat = 520
    /// Floor so short tabs (Agents, General) don't collapse the window — cream space
    /// below a top-aligned stack reads as composure; a window that snaps between
    /// 205 and 505 pt reads as a bug.
    static let minContentHeight: CGFloat = 400

    /// Owned by `SettingsWindow` so re-opening can switch tabs on a live window.
    @EnvironmentObject var selection: SettingsSelection

    var body: some View {
        VStack(spacing: 0) {
            OWTabBar(selection: $selection.tab, needsAttention: needsAttention)

            // No ScrollView: it reports an ambiguous ideal height, and NSHostingController
            // sizes the window from that — which yields a degenerate window. Each tab's
            // content is modest, so the window simply sizes to the active tab.
            Group {
                switch selection.tab {
                case .general:   GeneralTab()
                case .dictation: DictationTab()
                case .voice:     VoiceTab()
                case .agents:    AgentsTab()
                case .advanced:  AdvancedTab()
                }
            }
            .padding(18)
            .frame(width: Self.contentWidth, alignment: .topLeading)
            .frame(minHeight: Self.minContentHeight, alignment: .top)
        }
        .frame(width: Self.contentWidth)
        .background(OWColor.page)
        .background(OWWindowBackground())
    }

    /// A required grant is missing — badges the General (logo) tab from anywhere.
    private var needsAttention: Bool {
        !accessibilityManager.isGranted || !dictationManager.recorder.micPermission
    }
}
