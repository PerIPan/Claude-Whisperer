import SwiftUI
import OpenWhispererKit

/// Entry point. Normal launch runs the SwiftUI menu-bar app; `--serve-tts` runs a headless
/// native-TTS HTTP server (for testing/diagnostics and CI) without the GUI.
@main
enum OpenWhispererMain {
    static func main() {
        if CommandLine.arguments.contains("--serve-tts") {
            ServeTTSMode.run()
        } else if let flagIndex = CommandLine.arguments.firstIndex(of: "--diag-parakeet") {
            // Headless Parakeet probe — downloads/loads the TDT v3 CoreML models, then
            // transcribes any audio files listed after the flag. Exercises the full STT
            // path (model fetch → ANE compile → decode) without mic/TCC:
            //   swift run OpenWhisperer --diag-parakeet clip1.wav clip2.wav
            let files = CommandLine.arguments.suffix(from: flagIndex + 1)
            Task {
                do {
                    print("DIAG: preparing Parakeet TDT v3 (downloads ~460 MB if uncached)…")
                    let t0 = Date()
                    let parakeet = ParakeetTranscriber()
                    try await parakeet.prepare()
                    print("DIAG: Parakeet LOADED OK in \(Int(-t0.timeIntervalSinceNow))s")
                    for path in files {
                        let t1 = Date()
                        let text = try await parakeet.transcribe(
                            url: URL(fileURLWithPath: path), language: nil)
                        print("DIAG: \(path) [\(Int(-t1.timeIntervalSinceNow * 1000)) ms] → \(text)")
                    }
                } catch {
                    print("DIAG: Parakeet FAILED: \(error)")
                    print("DIAG: localizedDescription: \(error.localizedDescription)")
                    exit(1)
                }
                exit(0)
            }
            Task {
                try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
                print("DIAG: TIMEOUT after 600s — Parakeet probe did not complete")
                exit(2)
            }
            RunLoop.main.run()
        } else {
            OpenWhispererApp.main()
        }
    }
}

struct OpenWhispererApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Register custom fonts before SwiftUI composes the first layout pass.
        registerBundledFonts()
    }

    var body: some Scene {
        // Plain menu dropdown — the settings themselves live in the branded
        // SettingsWindow (see Settings/SettingsWindow.swift).
        MenuBarExtra {
            MenuBarMenu(appDelegate: appDelegate)
        } label: {
            // Always-visible first-run signal: hourglass while the models load, waveform once ready.
            MenuBarStatusIcon(dictation: appDelegate.dictationManager,
                              server: appDelegate.serverManager,
                              accessibility: appDelegate.accessibilityManager)
        }
    }
}

/// Menubar dropdown contents.
private struct MenuBarMenu: View {
    let appDelegate: AppDelegate
    @ObservedObject private var overlay = TranscriptionOverlay.shared

    var body: some View {
        Button("Settings…") {
            SettingsWindow.show(tab: SettingsWindow.preferredTab(for: appDelegate),
                                appDelegate: appDelegate)
        }
        .keyboardShortcut(",", modifiers: .command)

        Toggle("Show Overlay", isOn: Binding(
            get: { overlay.isVisible },
            set: { $0 ? overlay.show() : overlay.hide() }
        ))

        Divider()

        Button("Quit Open Whisperer") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

/// The menu-bar icon. Shows an hourglass while a model is still loading (most visible on the
/// very first launch), a speaker while a dictated turn is armed to be spoken (the will-speak
/// indicator), an exclamation badge when a required permission is missing, and the waveform
/// otherwise. The badge is the only permission signal visible with the window closed.
private struct MenuBarStatusIcon: View {
    @ObservedObject var dictation: DictationManager
    @ObservedObject var server: ServerManager
    @ObservedObject var accessibility: AccessibilityManager

    var body: some View {
        let loading = (!dictation.sttModelReady && !dictation.sttFailed) || server.status == .starting
        let needsGrant = !accessibility.isGranted || !dictation.recorder.micPermission
        if loading {
            Image(systemName: "hourglass")
        } else if needsGrant {
            Image(systemName: "exclamationmark.triangle")
        } else {
            Image(systemName: dictation.speakArmed ? "speaker.wave.2" : "waveform")
        }
    }
}
