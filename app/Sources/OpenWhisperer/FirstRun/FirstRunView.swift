import SwiftUI
import OpenWhispererKit

/// Which pane is showing. Outside the view so the window can be re-fronted onto a
/// specific pane, the same reason `SettingsSelection` exists.
final class FirstRunSelection: ObservableObject {
    @Published var pane: FirstRunPane = .permissions
}

/// First-run setup: four panes, skippable throughout, with download status in the chrome.
///
/// Replaces what first launch used to do — open Settings on General after 0.5 s, then drop
/// an `InstructionWindow` full of JSON over it a second later, while 1.5 GB downloaded
/// behind. Settings is where you return to change one thing; it was standing in for a
/// screen that did not exist.
///
/// Three rules this view exists to keep:
///
/// - **Nothing blocks.** Every pane advances (`FirstRunPane.blocksAdvance` is the named
///   rule), and "Skip setup" is always present. A user who skips lands exactly where they
///   landed before this sheet existed, so the worst case is the old behaviour.
/// - **No second source of truth.** Every control writes the same file under
///   `Paths` that Settings writes. There is no first-run copy of a preference to drift.
/// - **Download status is chrome, not a pane.** The model fetch starts at launch and
///   outlives all four panes, so it lives in a strip that is visible from the first pane
///   to the last.
struct FirstRunView: View {
    @EnvironmentObject var selection: FirstRunSelection
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var dictationManager: DictationManager
    @EnvironmentObject var accessibilityManager: AccessibilityManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(OWColor.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selection.pane.title)
                            .font(OWFont.body(15).weight(.semibold))
                            .foregroundColor(OWColor.ink)
                        Text(selection.pane.subtitle)
                            .font(OWFont.caption(11))
                            .foregroundColor(OWColor.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    pane
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 330)

            Divider().overlay(OWColor.divider)
            downloadStrip
            Divider().overlay(OWColor.divider)
            footer
        }
        .frame(width: 520)
        .background(OWColor.page)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 8) {
            ForEach(FirstRunPane.allCases, id: \.self) { p in
                Circle()
                    .fill(p == selection.pane ? OWColor.accent
                          : (p.rawValue < selection.pane.rawValue ? OWColor.accent.opacity(0.35)
                                                                  : OWColor.inkFaint.opacity(0.3)))
                    .frame(width: 7, height: 7)
            }
            Text("Step \(selection.pane.step) of \(FirstRunPane.count)")
                .font(OWFont.caption(10))
                .foregroundColor(OWColor.inkFaint)
                .padding(.leading, 2)

            Spacer()

            Button("Skip setup") { FirstRunWindow.finish() }
                .buttonStyle(.plain)
                .font(OWFont.caption(11))
                .foregroundColor(OWColor.inkSoft)
                .help("Close setup. Everything here is also in Settings, and you can reopen this from the menubar.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var pane: some View {
        switch selection.pane {
        case .permissions:
            FirstRunPermissionsPane()
                .environmentObject(dictationManager)
                .environmentObject(accessibilityManager)
        case .dictate:
            FirstRunDictatePane().environmentObject(dictationManager)
        case .voice:
            FirstRunVoicePane().environmentObject(serverManager)
        case .agent:
            FirstRunAgentPane()
        }
    }

    /// The one piece of state that spans every pane. STT reports real percentages
    /// (`DictationManager` threads WhisperKit's `progressCallback` through), so show them.
    /// TTS has no progress instrumentation, so it gets honest indeterminate copy rather
    /// than a bar that would be making its number up.
    private var downloadStrip: some View {
        HStack(spacing: 8) {
            switch downloadState {
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundColor(OWColor.danger)
                Text(message).font(OWFont.caption(11)).foregroundColor(OWColor.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            case .working(let message):
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
                Text(message).font(OWFont.caption(11)).foregroundColor(OWColor.inkSoft)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10)).foregroundColor(OWColor.live)
                Text("Speech and voice models ready.")
                    .font(OWFont.caption(11)).foregroundColor(OWColor.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private enum DownloadState {
        case working(String)
        case failed(String)
        case ready
    }

    private var downloadState: DownloadState {
        if dictationManager.sttFailed {
            return .failed(dictationManager.sttStatus ?? "Speech model failed to load.")
        }
        if !dictationManager.sttModelReady {
            // `sttStatus` carries "Downloading… 42% of ~1.5 GB (one-time)" and, after that,
            // "Download done — compiling for the Neural Engine…". The compile is a long
            // silent pause; without that second line it reads as a hang.
            return .working(dictationManager.sttStatus ?? "Preparing the speech model…")
        }
        if serverManager.status == .starting {
            return .working("Preparing the voice…")
        }
        return .ready
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !selection.pane.isFirst {
                Button("Back") {
                    if let p = selection.pane.previous { selection.pane = p }
                }
                .buttonStyle(OWRowButtonStyle())
                .frame(width: 90)
            }
            Spacer()
            Button(selection.pane.isLast ? "Done" : "Next") {
                if let next = selection.pane.next {
                    selection.pane = next
                } else {
                    FirstRunWindow.finish()
                }
            }
            .buttonStyle(OWPrimaryButtonStyle())
            .frame(width: 110)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
