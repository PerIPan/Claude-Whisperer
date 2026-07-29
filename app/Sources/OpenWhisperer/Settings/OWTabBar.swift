import SwiftUI

/// The branded tab strip for the Settings window.
///
/// Deliberately NOT the native `Settings`-scene `TabView`: that renders a system
/// AppKit toolbar strip whose background/tint cannot be recolored on any macOS
/// version, which would leave a gray band above our cream body. Drawing our own
/// keeps the window one continuous cream/gold surface.
///
/// Native tabs give keyboard/VoiceOver handling for free; since we draw our own we
/// add it explicitly here (arrow-key selection + selected traits).
struct OWTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                OWTabButton(tab: tab, isSelected: selection == tab) { selection = tab }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(OWColor.page)
        // Hairline seam so the bar reads as chrome without a heavy border.
        .overlay(alignment: .bottom) {
            Rectangle().fill(OWColor.line).frame(height: 1)
        }
        .focusable()
        .onMoveCommand { direction in
            let all = SettingsTab.allCases
            guard let i = all.firstIndex(of: selection) else { return }
            switch direction {
            case .left:  if i > 0 { selection = all[i - 1] }
            case .right: if i < all.count - 1 { selection = all[i + 1] }
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }
}

private struct OWTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .regular))
                Text(tab.title)
                    .font(OWFont.body(11))
            }
            .foregroundColor(isSelected ? OWColor.onAccent : OWColor.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? OWColor.accent
                                     : (isHovered ? OWColor.pillFill : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
