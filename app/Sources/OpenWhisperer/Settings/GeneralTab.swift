import SwiftUI
import ServiceManagement

/// "Is everything OK" tab: first-run/model health, startup, the canonical permission
/// list, and the version footer.
struct GeneralTab: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var setupManager: SetupManager
    @EnvironmentObject var dictationManager: DictationManager
    @EnvironmentObject var accessibilityManager: AccessibilityManager

    @State private var launchAtLogin = false
    @State private var diagnosticsCopied = false
    @State private var selectedMode: InteractionMode = .holdToTalk

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            setupProgressSection
            modelLoadingBanner

            OWCard {
                VStack(alignment: .leading, spacing: 10) {
                    OWCardHeader(title: "Startup", icon: "power",
                                 help: "Launch Open Whisperer automatically when you log in.")
                    OWCheckbox(label: "Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            let service = SMAppService.mainApp
                            do {
                                if enabled { try service.register() } else { try service.unregister() }
                            } catch {
                                NSLog("Login item toggle failed: \(error)")
                                DispatchQueue.main.async { launchAtLogin = service.status == .enabled }
                            }
                        }
                }
            }

            OWCard {
                VStack(alignment: .leading, spacing: 8) {
                    OWCardHeader(title: allPermissionsGranted ? "Permissions" : "Permissions Required",
                                 icon: "lock.shield",
                                 help: "macOS grants Open Whisperer needs: Accessibility (type into the focused app), Microphone (record dictation), and Speech Recognition (hands-free wake words). Click a row to open Settings.")

                    ModernDiagnosticRow(label: "Accessibility", ok: accessibilityManager.isGranted)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .help("Lets the app type dictated text into the focused app — the clipboard is never touched. Click to open Settings.")

                    ModernDiagnosticRow(label: "Microphone", ok: dictationManager.recorder.micPermission)
                        .contentShape(Rectangle())
                        .onTapGesture { dictationManager.recorder.openMicSettings() }
                        .help("Lets the app record your microphone to capture dictation. Click to open Settings.")

                    // Hands-free only — don't nag for a grant the current mode never uses.
                    if selectedMode == .handsFree {
                        ModernDiagnosticRow(label: "Speech Recognition",
                                            ok: dictationManager.keywordDetector.permissionGranted)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .help("Hands-Free only: Apple Speech detects the wake words \"initiate\" and \"hold on\". Click to open Settings.")
                    }
                }
            }

            HStack {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(OWFont.caption())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .onAppear {
            selectedMode = InteractionMode.load()
            // Re-read mic/speech authorization on every appearance so a grant (or
            // revocation) made in System Settings shows up without relaunching.
            // Accessibility has its own continuous poll. Speech only in hands-free —
            // otherwise we'd re-request a permission that mode never uses.
            dictationManager.recorder.checkPermission()
            if selectedMode == .handsFree {
                dictationManager.keywordDetector.checkPermission()
            }
            // SMAppService.mainApp.status is a synchronous XPC call to launchservicesd and
            // can block the main thread for seconds; resolve it off-main.
            DispatchQueue.global(qos: .userInitiated).async {
                let enabled = SMAppService.mainApp.status == .enabled
                DispatchQueue.main.async { launchAtLogin = enabled }
            }
        }
    }

    /// Speech Recognition is hands-free-only, so it counts toward "all granted" only in
    /// that mode — otherwise a hold-to-talk user who never granted it reads as incomplete.
    private var allPermissionsGranted: Bool {
        let speechNeeded = selectedMode == .handsFree
        return accessibilityManager.isGranted
            && dictationManager.recorder.micPermission
            && (!speechNeeded || dictationManager.keywordDetector.permissionGranted)
    }

    // MARK: - First-run signals

    @ViewBuilder
    private var setupProgressSection: some View {
        if case .inProgress(let step) = setupManager.state {
            OWCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step).font(OWFont.caption()).foregroundColor(.secondary)
                    ProgressView(value: setupManager.progress)
                        .progressViewStyle(.linear)
                        .tint(OWColor.accent)
                }
            }
        } else if case .failed(let reason) = setupManager.state {
            OWCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(OWFont.caption())
                        .foregroundColor(OWColor.danger)
                    Button("Retry Setup") {
                        setupManager.resetAndRerun { success in
                            guard success else { return }
                            DispatchQueue.main.async { serverManager.startAll() }
                        }
                    }
                    .buttonStyle(OWPrimaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var modelLoadingBanner: some View {
        let sttLoading = !dictationManager.sttModelReady && !dictationManager.sttFailed
        let ttsLoading = serverManager.status == .starting
        if dictationManager.sttFailed {
            OWCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(OWColor.danger)
                        Text("Speech model failed to load")
                            .font(OWFont.body(11).weight(.semibold))
                            .foregroundColor(OWColor.ink)
                    }
                    Text(dictationManager.sttStatus ?? "Speech model failed to load.")
                        .font(OWFont.caption(11))
                        .foregroundColor(OWColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Button(action: { dictationManager.retrySTT() }) {
                            Label("Retry", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OWRowButtonStyle(tinted: true))
                        Button(action: {
                            Diagnostics.copyToClipboard(dictation: dictationManager, server: serverManager)
                            diagnosticsCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { diagnosticsCopied = false }
                        }) {
                            Label(diagnosticsCopied ? "Copied" : "Copy Diagnostics",
                                  systemImage: diagnosticsCopied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OWRowButtonStyle())
                    }
                    if ttsLoading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Voice model still loading…")
                                .font(OWFont.caption(11))
                                .foregroundColor(OWColor.inkSoft)
                        }
                    }
                }
            }
        } else if sttLoading || ttsLoading {
            OWCard {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Preparing models…")
                            .font(OWFont.body(11).weight(.semibold))
                            .foregroundColor(OWColor.ink)
                        Text(sttLoading
                             ? (dictationManager.sttStatus ?? "Loading the speech model…")
                             : "Loading the voice model…")
                            .font(OWFont.caption(11))
                            .foregroundColor(OWColor.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
