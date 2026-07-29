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

    @State private var selection: SettingsTab

    init(initialTab: SettingsTab = .general) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            OWTabBar(selection: $selection)

            // No ScrollView: it reports an ambiguous ideal height, and NSHostingController
            // sizes the window from that — which yields a degenerate window. Each tab's
            // content is modest, so the window simply sizes to the active tab.
            Group {
                switch selection {
                case .general:   GeneralTab()
                case .dictation: DictationTab()
                case .voice:     VoiceTab()
                case .agents:    AgentsTab()
                case .advanced:  AdvancedTab()
                }
            }
            .padding(14)
            .frame(width: Self.contentWidth, alignment: .leading)
        }
        .frame(width: Self.contentWidth)
        .background(OWColor.page)
        .background(OWWindowBackground())
    }
}
