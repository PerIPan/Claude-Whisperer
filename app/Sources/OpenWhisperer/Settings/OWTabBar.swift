import AppKit
import SwiftUI

/// The branded tab strip for the Settings window.
///
/// Deliberately NOT the native `Settings`-scene `TabView`: that renders a system
/// AppKit toolbar strip whose background/tint cannot be recolored on any macOS
/// version, which would leave a gray band above our cream body. Drawing our own
/// keeps the window one continuous cream/gold surface.
///
/// Layout: the named tabs fill from the left, then the version string, then General
/// pinned right as the app logo.
struct OWTabBar: View {
    @Binding var selection: SettingsTab
    /// Badges the General (logo) tab — the only in-window signal that a required
    /// grant is missing when you're not already looking at General.
    var needsAttention: Bool = false

    private var namedTabs: [SettingsTab] { SettingsTab.allCases.filter { !$0.usesAppLogo } }
    private var logoTab: SettingsTab? { SettingsTab.allCases.first { $0.usesAppLogo } }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(namedTabs) { tab in
                OWTabButton(tab: tab, isSelected: selection == tab) { selection = tab }
            }

            // Version lives in General's About card, not here — in the strip it read
            // as a fifth, disabled tab.
            Spacer(minLength: 12)

            if let logoTab {
                OWTabButton(tab: logoTab,
                            isSelected: selection == logoTab,
                            needsAttention: needsAttention) { selection = logoTab }
                    .frame(width: 54)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(OWColor.page)
        // Warm hairline seam so the bar reads as chrome. (The system focus ring is
        // suppressed below — it drew as a blue band across the cream.)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OWColor.line).frame(height: 1)
        }
        .focusable()
        .focusEffectDisabled()
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
    var needsAttention: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    /// Every tab's label occupies the same height so the selected gold pill is uniform
    /// (a 26pt logo next to a 15pt symbol + 11pt text otherwise leaves the logo pill short).
    private static let labelHeight: CGFloat = 35

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if tab.usesAppLogo, let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .overlay(alignment: .topTrailing) {
                            if needsAttention {
                                Circle()
                                    .fill(OWColor.warn)
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(OWColor.page, lineWidth: 1.5))
                                    .offset(x: 3, y: -2)
                            }
                        }
                } else {
                    Image(systemName: tab.icon)
                        .font(.system(size: 15, weight: .regular))
                    Text(tab.title)
                        .font(OWFont.body(11))
                }
            }
            .frame(height: Self.labelHeight)
            .foregroundColor(isSelected ? OWColor.onAccent : OWColor.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? OWColor.accent
                                     : (isHovered ? OWColor.pillFill : Color.clear))
            )
            // A tinted fill can't recolor a bitmap logo, so give the logo tab a second
            // selection cue that doesn't rely on foregroundColor.
            .overlay(alignment: .bottom) {
                if isSelected && tab.usesAppLogo {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(OWColor.accentDeep)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
