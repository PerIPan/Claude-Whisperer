import SwiftUI

/// Root of the branded Settings window: our own tab bar over the selected tab's body.
/// Fixed width; each tab reports its own height and the hosting window resizes to fit.
struct SettingsView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var setupManager: SetupManager
    @EnvironmentObject var dictationManager: DictationManager
    @EnvironmentObject var accessibilityManager: AccessibilityManager
    /// Observed so a theme change re-renders the whole window. Without this only the tab
    /// that owns the picker repainted, and the rest kept its old colours until you
    /// switched tabs and forced a rebuild.
    @ObservedObject private var themeManager = ThemeManager.shared

    /// Fixed content size (the window is not user-resizable). The height is explicit
    /// rather than derived from each tab: sizing to content clipped the tallest tab
    /// (Dictation) and made the window jump on every switch. With a fixed height the
    /// ScrollView below has an unambiguous ideal size, so nothing is ever cut off.
    static let contentWidth: CGFloat = 440
    static let contentHeight: CGFloat = 620

    /// Owned by `SettingsWindow` so re-opening can switch tabs on a live window.
    @EnvironmentObject var selection: SettingsSelection

    var body: some View {
        VStack(spacing: 0) {
            OWTabBar(selection: $selection.tab, needsAttention: needsAttention)

            ScrollView {
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
            }
            .frame(width: Self.contentWidth, height: Self.contentHeight)
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
