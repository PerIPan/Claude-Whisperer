import AppKit
import SwiftUI
import ServiceManagement
import OpenWhispererKit

// Design tokens (OWColor, OWFont) live in Theme.swift; the shared OW* controls
// live in SettingsControls.swift.

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var setupManager: SetupManager
    @EnvironmentObject var dictationManager: DictationManager
    @EnvironmentObject var accessibilityManager: AccessibilityManager
    @State private var autoSubmit = false
    @State private var autoFocusEnabled = false
    @State private var autoFocusReturn = false
    @State private var focusAppName = ""
    @State private var focusSelection = "Code"  // visual default; only written on explicit toggle
    @State private var customFocusApp = ""
    @State private var installedApps: [AppEntry] = []
    @State private var saveDebounce: DispatchWorkItem?
    @State private var selectedPTTKey = "ctrl"
    @State private var selectedMode: InteractionMode = .holdToTalk
    @State private var silenceThreshold: Int = 3
    @State private var selectedVolume: Double = 1.0
    @State private var selectedVoice = "af_heart"
    @State private var selectedSpeed: Double = Double(TTSSpeed.default)
    @State private var selectedLanguage = "en"
    @State private var selectedStyle = "normal"
    @State private var selectedResponse = "voice"
    @State private var vocabulary = ""                              // custom STT glossary (1.10)
    @State private var overlayStyle: OverlayStyle = .defaultStyle   // overlay analyzer style (1.10)
    @State private var showStoppedBanner = false
    @State private var pttKeyChanged = false
    @State private var selectedPlatform: Platform = .claudeCode
    @State private var hookApplied = false
    @State private var applyMessage = ""
    @State private var serverReachable = false
    @State private var deletedModelsBanner = false
    @State private var launchAtLogin = false
    @State private var diagnosticsCopied = false
    @State private var voiceSettingsExpanded = false  // always collapsed by default on launch
    @State private var setupExpanded = false   // always collapsed by default on launch
    @State private var serverExpanded = false  // always collapsed by default on launch
    // logsExpanded removed — merged into serverExpanded
    @ObservedObject private var overlay = TranscriptionOverlay.shared

    // Full Kokoro-82M v1.0 roster (verified against onnx-community/Kokoro-82M-v1.0-ONNX
    // on 2026-07-01). Grouped by language for the nested-submenu picker. Non-default
    // voices download on first selection via KokoroTTS.ensureVoicePack. The bare `af`
    // alias is intentionally omitted (it is a default mix, not a named voice).
    private static let voiceGroups: [(group: String, options: [(id: String, label: String)])] = {
        TTSVoiceRegistry.groups.map { group in
            (group.name, group.voices.map { ($0.id, "\($0.name) (\($0.gender.prefix(1)))") })
        }
    }()

    private static let allVoices: [(id: String, label: String)] = {
        TTSVoiceRegistry.allVoices.map { ($0.id, "\($0.name) (\($0.gender.prefix(1)))") }
    }()

    private static let languages: [(id: String, label: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("ru", "Russian"),
        ("pl", "Polish"),
        ("tr", "Turkish"),
        ("uk", "Ukrainian"),
        ("sv", "Swedish"),
    ]

    private static let styleLevels: [(id: String, label: String)] = [
        ("terse", "Terse"),
        ("normal", "Normal"),
        ("rich", "Rich"),
        ("full", "Full"),
    ]

    // When replies are spoken. "voice" (default) = only dictated turns; matches
    // the tts_response_mode values read by voice-context.sh / codex-tts-hook.sh.
    private static let responseModes: [(id: String, label: String)] = [
        ("voice", "when Voice"),
        ("always", "Always"),
    ]

    private static let focusApps: [(id: String, label: String)] = [
        ("Code", "VS Code"),
        ("Code - Insiders", "VS Code Insiders"),
        ("Cursor", "Cursor (AI Editor)"),
        ("Windsurf", "Windsurf (AI Editor)"),
        ("Zed", "Zed (Editor)"),
        ("Xcode", "Xcode (Apple IDE)"),
        ("Sublime Text", "Sublime Text (Editor)"),
        ("Nova", "Nova (Panic)"),
        ("Fleet", "Fleet (JetBrains)"),
        ("Claude", "Claude (Desktop)"),
        ("Terminal", "Terminal (macOS)"),
        ("iTerm2", "iTerm2 (Terminal)"),
        ("Warp", "Warp (Terminal)"),
        ("Alacritty", "Alacritty (Terminal)"),
        ("Ghostty", "Ghostty (Terminal)"),
        ("CUSTOM", "CUSTOM"),
    ]

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.bottom, 12)

            setupProgressSection

            modelLoadingBanner

            voiceInputCard
                .padding(.bottom, 8)

            voiceSettingsCard
                .padding(.bottom, 8)

            automationCard
                .padding(.bottom, 8)

            setupCard
                .padding(.bottom, 8)

            serverCard
                .padding(.bottom, 8)

            footerSection
        }
        .padding(14)
        .font(OWFont.body())
        .foregroundStyle(OWColor.ink)
        .tint(OWColor.accent)
        .frame(width: 310)
        // Native AppKit controls replaced with custom OWMenuPicker/OWCheckbox.
        // Warm solid surface (no material) to match openwhisperer.com; window chrome
        // tinted to match in both light + dark via OWWindowBackground.
        .background(OWColor.page)
        .background(OWWindowBackground())
        .onAppear {
            selectedPlatform = Platform.load()
            // SMAppService.mainApp.status is a synchronous XPC call to launchservicesd and
            // can block the main thread for seconds (freezing the menu). Resolve it off the
            // main thread and assign the flag back on main.
            DispatchQueue.global(qos: .userInitiated).async {
                let enabled = SMAppService.mainApp.status == .enabled
                DispatchQueue.main.async { launchAtLogin = enabled }
            }
            autoSubmit = FileManager.default.fileExists(atPath: Paths.autoSubmitFlag.path)
            autoFocusEnabled = FileManager.default.fileExists(atPath: Paths.autoFocusApp.path)
            autoFocusReturn = FileManager.default.fileExists(atPath: Paths.autoFocusReturn.path)
            if installedApps.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async {
                    let apps = InstalledApps.all()
                    DispatchQueue.main.async { installedApps = apps }
                }
            }
            if let saved = try? String(contentsOf: Paths.autoFocusApp, encoding: .utf8),
               !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let value = saved.trimmingCharacters(in: .whitespacesAndNewlines)
                focusAppName = value
                switch FocusTarget.parse(value) {
                case .bundleID(let bid):
                    focusSelection = bid              // installed-app pick ("bundleid:" tagged)
                case .name(let name):
                    if Self.focusApps.contains(where: { $0.id == name }) {
                        focusSelection = name         // curated favorite
                    } else {
                        focusSelection = "CUSTOM"
                        customFocusApp = name         // typed custom name (or legacy value)
                    }
                }
            }
            if let savedKey = try? String(contentsOf: Paths.pttHotkey, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
               let key = PTTKey(rawValue: savedKey) {
                selectedPTTKey = savedKey
                TranscriptionOverlay.shared.pttKeyLabel = key.label
            }
            if let savedVoice = try? String(contentsOf: Paths.ttsVoice, encoding: .utf8),
               !savedVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let voice = savedVoice.trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.allVoices.contains(where: { $0.id == voice }) {
                    selectedVoice = voice
                }
            }
            if let savedLang = try? String(contentsOf: Paths.sttLanguage, encoding: .utf8),
               !savedLang.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lang = savedLang.trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.languages.contains(where: { $0.id == lang }) {
                    selectedLanguage = lang
                }
            }
            if let savedStyle = try? String(contentsOf: Paths.ttsStyle, encoding: .utf8),
               !savedStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let style = savedStyle.trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.styleLevels.contains(where: { $0.id == style }) {
                    selectedStyle = style
                }
            }
            if let savedResponse = try? String(contentsOf: Paths.ttsResponseMode, encoding: .utf8),
               !savedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let mode = savedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.responseModes.contains(where: { $0.id == mode }) {
                    selectedResponse = mode
                }
            }
            selectedVolume = Double(TTSVolume.parse(try? String(contentsOf: Paths.ttsVolume, encoding: .utf8)))
            selectedSpeed = Double(TTSSpeed.parse(try? String(contentsOf: Paths.ttsSpeed, encoding: .utf8)))
            selectedMode = InteractionMode.load()
            if let savedStr = try? String(contentsOf: Paths.silenceThreshold, encoding: .utf8),
               let saved = Int(savedStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                silenceThreshold = saved
            }
            vocabulary = (try? String(contentsOf: Paths.sttVocabulary, encoding: .utf8)) ?? ""
            overlayStyle = OverlayStyle.parse(try? String(contentsOf: Paths.overlayStyle, encoding: .utf8))
            // Permissions live inside the (collapsed) Server & Logs card — auto-expand it when a
            // required grant is missing so a first-run user still sees "Permissions Required".
            if !allPermissionsGranted { serverExpanded = true }
            refreshDiagnostics()
        }
    }

    /// "1×", "1.15×", "1.2×" — trims trailing zeros so the slider readout stays tidy.
    /// Formats a playback multiplier (speed or volume) as a trimmed "1.5×" / "1×".
    private func multiplierLabel(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s + "×"
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text("Open Whisperer")
                .font(OWFont.title(17))
                .foregroundColor(OWColor.ink)
            Spacer()
        }
    }

    // MARK: - Setup Progress (conditional)

    @ViewBuilder
    private var setupProgressSection: some View {
        if case .inProgress(let step) = setupManager.state {
            OWCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step)
                        .font(OWFont.caption())
                        .foregroundColor(.secondary)
                    ProgressView(value: setupManager.progress)
                        .progressViewStyle(.linear)
                        .tint(OWColor.accent)
                }
            }
            .padding(.bottom, 8)
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
            .padding(.bottom, 8)
        }
    }

    // MARK: - Model Loading Banner (first-run signal)

    /// Prominent banner shown only while a model is still loading — most visible on the very
    /// first launch (download + Neural-Engine compile can take 1–2 min). Disappears once ready.
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
                            Label("Retry", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
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
                    // The failure card replaces the loading banner, so keep the
                    // still-loading TTS state visible rather than hiding it.
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
            .padding(.bottom, 10)
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
            .padding(.bottom, 10)
        }
    }

    // MARK: - Voice Input Card

    private var voiceInputCard: some View {
        OWCard {
            VStack(alignment: .leading, spacing: 10) {
                OWCardHeader(title: "Voice Input", icon: "mic.fill",
                             help: "How you start dictation — Press-to-Talk, Hold-to-Talk, or Hands-Free — plus the trigger key and how the app listens.")

                // Mode dropdown
                OWPickerRow(label: "Mode", labelWidth: 52) {
                    OWMenuPicker(
                        selection: $selectedMode,
                        options: InteractionMode.allCases.map { (id: $0, label: $0.label) }
                    )
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: selectedMode) { _, newValue in
                    newValue.save()
                    dictationManager.interactionMode = newValue
                }

                // Mode description hint — wrap to multiple lines instead of truncating
                Text(selectedMode.description)
                    .font(OWFont.caption(11))
                    .foregroundColor(OWColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !dictationManager.recorder.micPermission {
                    OWInternalDivider()

                    Button(action: { dictationManager.recorder.openMicSettings() }) {
                        Label("Grant Microphone Access", systemImage: "mic.slash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(OWRowButtonStyle())

                    Text("Required for built-in dictation")
                        .font(OWFont.caption())
                        .foregroundColor(OWColor.warn)
                } else {
                    OWInternalDivider()

                    // Recording state + PTT key — aligned icon column
                    HStack(spacing: 8) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: stateColor.opacity(0.5), radius: stateGlows ? 3 : 0)
                            .frame(width: 16)
                        Text(stateLabel)
                            .font(OWFont.body(11))
                            .foregroundColor(OWColor.ink)

                        Spacer()

                        if selectedMode != .handsFree {
                            OWMenuPicker(
                                selection: $selectedPTTKey,
                                options: PTTKey.allCases.map { (id: $0.rawValue, label: $0.label) }
                            )
                            .frame(width: 76)
                        }
                    }
                    .onChange(of: selectedPTTKey) { _, newValue in
                        try? newValue.write(to: Paths.pttHotkey, atomically: true, encoding: .utf8)
                        if let key = PTTKey(rawValue: newValue) {
                            TranscriptionOverlay.shared.pttKeyLabel = key.label
                        }
                        pttKeyChanged = true
                    }

                    // Hands-free: silence threshold
                    if selectedMode == .handsFree {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.slash")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            Text("Silence")
                                .font(OWFont.body(11))
                            Spacer()
                            OWMenuPicker(
                                selection: $silenceThreshold,
                                options: [3, 4, 5, 7, 10, 20].map { (id: $0, label: "\($0)s") }
                            )
                            .frame(width: 76)
                            .onChange(of: silenceThreshold) { _, newValue in
                                let str = String(newValue)
                                try? str.write(to: Paths.silenceThreshold, atomically: true, encoding: .utf8)
                                dictationManager.recorder.silenceThresholdSeconds = TimeInterval(newValue)
                            }
                        }

                        if dictationManager.isCalibrating {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Calibrating microphone...")
                                    .font(OWFont.caption())
                                    .foregroundColor(OWColor.warn)
                            }
                        }

                        if dictationManager.ttsPlaying {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(OWColor.accentDeep)
                                Text("say \"hold on\" to interrupt TTS")
                                    .font(OWFont.caption())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Transcription overlay — one control: OFF, or pick an analyzer style
                    // (which also shows the overlay). The chosen style persists across OFF/ON.
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 11))
                            .foregroundColor(overlay.isVisible ? OWColor.live : OWColor.inkFaint)
                            .frame(width: 16)
                        Text("Overlay")
                            .font(OWFont.body(11))
                        Spacer()
                        OWMenuPicker(
                            selection: Binding(
                                get: { overlay.isVisible ? overlayStyle.rawValue : "off" },
                                set: { newValue in
                                    if newValue == "off" {
                                        overlay.hide()
                                    } else {
                                        let style = OverlayStyle.parse(newValue)
                                        overlayStyle = style
                                        try? style.rawValue.write(to: Paths.overlayStyle, atomically: true, encoding: .utf8)
                                        TranscriptionOverlay.shared.analyzerStyle = style
                                        overlay.show()
                                    }
                                }
                            ),
                            options: [
                                (id: "off", label: "OFF"),
                                (id: OverlayStyle.wave.rawValue, label: "Wave"),
                                (id: OverlayStyle.ledBars.rawValue, label: "LED Bars"),
                                (id: OverlayStyle.graph.rawValue, label: "Graph"),
                                (id: OverlayStyle.curtain.rawValue, label: "Curtain")
                            ]
                        )
                        .frame(width: 96)
                    }

                    // Hotkey-change notice
                    if pttKeyChanged {
                        InlineBadge(text: "Restart app to apply new hotkey", color: OWColor.warn)
                    }

                    // Error display
                    if let err = dictationManager.error {
                        InlineBadge(text: err, color: OWColor.danger)
                    }
                }
            }
        }
    }

    // MARK: - Voice Settings Card

    private var voiceSettingsCard: some View {
        OWCollapsibleCard(
            title: "Voice Settings",
            icon: "slider.horizontal.3",
            help: "Dictation language, the voice that reads replies aloud, how fast it's read, and Response — how much of a reply is spoken, and when.",
            expanded: $voiceSettingsExpanded
        ) {
            EmptyView()
        } expandedContent: {
            VStack(alignment: .leading, spacing: 10) {
                OWPickerRow(label: "Dictate in", labelWidth: 62) {
                    OWMenuPicker(selection: $selectedLanguage, options: Self.languages)
                        .frame(maxWidth: .infinity)
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    if newValue == "auto" {
                        try? FileManager.default.removeItem(at: Paths.sttLanguage)
                    } else {
                        try? newValue.write(to: Paths.sttLanguage, atomically: true, encoding: .utf8)
                    }
                }

                OWInternalDivider()

                // Custom vocabulary — edited in a pop-up window (keeps this card compact).
                // `vocabulary` is loaded on appear only to show the term count here.
                HStack(spacing: 8) {
                    Text("Custom vocabulary")
                        .font(OWFont.body(11))
                    Spacer()
                    let count = vocabulary.split(whereSeparator: \.isNewline)
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                    if count > 0 {
                        Text("\(count) term\(count == 1 ? "" : "s")")
                            .font(OWFont.body(11))
                            .foregroundColor(OWColor.inkSoft)
                    }
                    Button("Edit…") { VocabularyWindow.show() }
                        .buttonStyle(OWRowButtonStyle())
                }

                OWInternalDivider()

                OWPickerRow(label: "Voice", labelWidth: 62) {
                    OWGroupedMenuPicker(selection: $selectedVoice, groups: Self.voiceGroups)
                        .frame(maxWidth: .infinity)
                }
                .onChange(of: selectedVoice) { _, newValue in
                    try? newValue.write(to: Paths.ttsVoice, atomically: true, encoding: .utf8)
                }

                OWInternalDivider()

                OWPickerRow(label: "Speed", labelWidth: 62) {
                    HStack(spacing: 8) {
                        // Bounds MUST equal TTSSpeed.min/max (see TTSSpeed.swift).
                        Slider(value: $selectedSpeed, in: 0.7...1.5, step: 0.05)
                            .tint(OWColor.accent)
                            .help("How fast replies are read aloud. 1× is the default Kokoro rate; higher is faster. Spoken output only.")
                        Text(multiplierLabel(selectedSpeed))
                            .font(OWFont.body(11))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: selectedSpeed) { _, newValue in
                    try? String(format: "%.2f", newValue)
                        .write(to: Paths.ttsSpeed, atomically: true, encoding: .utf8)
                }

                OWInternalDivider()

                OWPickerRow(label: "Volume", labelWidth: 62) {
                    HStack(spacing: 8) {
                        // Bounds MUST equal TTSVolume.min/max (see TTSVolume.swift).
                        Slider(value: $selectedVolume, in: 0.3...2.0, step: 0.05)
                            .tint(OWColor.accent)
                            .help("How loud replies are read aloud. 1× is normal; higher is louder and may clip. Spoken output only.")
                        Text(multiplierLabel(selectedVolume))
                            .font(OWFont.body(11))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: selectedVolume) { _, newValue in
                    try? String(format: "%.2f", newValue)
                        .write(to: Paths.ttsVolume, atomically: true, encoding: .utf8)
                }

                // No visible separator between Volume and Response, but keep the same
                // gap (the divider was 0.5pt) so the rows don't move closer.
                Color.clear.frame(height: 0.5)

                // Both dropdowns are Response settings: spoken-summary length (left)
                // + when replies are spoken (right). One "Response" label, formatted
                // like the other rows.
                OWPickerRow(label: "Response", labelWidth: 62) {
                    HStack(spacing: 8) {
                        OWMenuPicker(selection: $selectedStyle, options: Self.styleLevels)
                            .frame(maxWidth: .infinity)
                            .onChange(of: selectedStyle) { _, newValue in
                                try? newValue.write(to: Paths.ttsStyle, atomically: true, encoding: .utf8)
                            }
                        OWMenuPicker(selection: $selectedResponse, options: Self.responseModes)
                            .frame(maxWidth: .infinity)
                            .help("When replies are spoken: when Voice = only dictated turns, Always = every turn.")
                            .onChange(of: selectedResponse) { _, newValue in
                                try? newValue.write(to: Paths.ttsResponseMode, atomically: true, encoding: .utf8)
                            }
                    }
                }

            }
        }
        .onChange(of: voiceSettingsExpanded) { _, newValue in
            if newValue {
                try? "open".write(to: Paths.voiceSettingsCardExpanded, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: Paths.voiceSettingsCardExpanded)
            }
        }
    }

    // MARK: - Automation Card

    private var automationCard: some View {
        OWCard {
            VStack(alignment: .leading, spacing: 10) {
                OWCardHeader(title: "App Focus Automation", icon: "gearshape.2",
                             help: "Force dictation into a chosen app: focus that app, type your words, optionally press Enter to submit, then (with return) hop back to where you were.")

                HStack(spacing: 20) {
                    OWCheckbox(label: "auto-focus", isOn: $autoFocusEnabled)
                    OWCheckbox(label: "auto-submit", isOn: $autoSubmit)
                }
                .onChange(of: autoSubmit) { _, enabled in
                    if enabled {
                        try? "on".write(to: Paths.autoSubmitFlag, atomically: true, encoding: .utf8)
                    } else {
                        do {
                            try FileManager.default.removeItem(at: Paths.autoSubmitFlag)
                        } catch {
                            NSLog("Failed to remove auto-submit flag: \(error)")
                        }
                    }
                }
                .onChange(of: autoFocusEnabled) { _, enabled in
                    if enabled {
                        if focusAppName.isEmpty {
                            focusAppName = focusSelection == "CUSTOM" ? customFocusApp : focusSelection
                        }
                        saveFocusApp()
                    } else {
                        try? FileManager.default.removeItem(at: Paths.autoFocusApp)
                    }
                }

                // Auto-focus sub-options — nested under the auto-focus toggle,
                // shown only while auto-focus is on.
                if autoFocusEnabled {
                    OWInternalDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        OWAppPicker(
                            selection: $focusSelection,
                            favorites: Self.focusApps.filter { $0.id != "CUSTOM" }
                                .map { AppEntry(bundleID: $0.id, name: $0.label) },
                            installed: installedApps
                        ) { id in
                            if id == "CUSTOM" {
                                focusAppName = customFocusApp
                            } else if installedApps.contains(where: { $0.bundleID == id }) {
                                focusAppName = FocusTarget.tag(bundleID: id)   // installed pick
                            } else {
                                focusAppName = id                             // curated favorite
                            }
                            saveFocusApp()
                        }
                        .frame(maxWidth: .infinity)

                        if focusSelection == "CUSTOM" {
                            TextField("App name", text: $customFocusApp)
                                .textFieldStyle(.roundedBorder)
                                .font(OWFont.body(11))
                                .onChange(of: customFocusApp) { _, newValue in
                                    if !newValue.isEmpty {
                                        focusAppName = newValue
                                        debouncedSaveFocusApp()
                                    }
                                }
                        }

                        OWCheckbox(label: "with return", isOn: $autoFocusReturn)
                            .onChange(of: autoFocusReturn) { _, enabled in
                                if enabled {
                                    try? "on".write(to: Paths.autoFocusReturn, atomically: true, encoding: .utf8)
                                } else {
                                    try? FileManager.default.removeItem(at: Paths.autoFocusReturn)
                                }
                            }
                    }
                    .padding(.leading, 6)
                }

                // Behavior hint — reflects the active auto-focus / with-return /
                // auto-submit combination.
                if let hint = automationHint {
                    Text(hint)
                        .font(OWFont.caption())
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// One-line description of what a dictation will do, given the active
    /// Automation toggles. Nil when no automation is on.
    private var automationHint: String? {
        if autoFocusEnabled {
            var steps = ["focus target app", "insert text"]
            if autoSubmit { steps.append("press enter") }
            if autoFocusReturn { steps.append("return to previous") }
            return steps.joined(separator: ", ")
        }
        if autoSubmit {
            return "enter is auto-applied after text insertion"
        }
        return nil
    }

    // MARK: - Setup Card

    private var setupCard: some View {
        OWCollapsibleCard(
            title: "Setup TTS for",
            icon: "hammer",
            help: "Wire up spoken replies for your CLI (Claude Code, Codex, Antigravity, or Pi) — Auto-Apply writes the hooks.",
            expanded: $setupExpanded
        ) {
            OWMenuPicker(
                selection: $selectedPlatform,
                options: Platform.allCases.map { (id: $0, label: $0.label) }
            )
            .frame(width: 104)
            .help("Which coding agent you're setting up. Claude/Codex/Antigravity get a hook + speak tool; Pi gets an extension.")
            .onChange(of: selectedPlatform) { _, newValue in
                newValue.save()
                refreshDiagnostics()
            }
        } expandedContent: {
            VStack(alignment: .leading, spacing: 8) {
                // Hook row — aligned label + info + apply
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Hook")
                            .font(OWFont.body(11))
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { ConfigManager.showHookInstructions(for: selectedPlatform) }

                    Button(action: {
                        let result = ConfigManager.applyHook(for: selectedPlatform)
                        hookApplied = result.success
                        applyMessage = result.message
                        refreshDiagnostics()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { applyMessage = "" }
                    }) {
                        Label(
                            hookApplied ? "Applied" : "Auto-Apply",
                            systemImage: hookApplied ? "checkmark.circle.fill" : "bolt.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OWRowButtonStyle(tinted: hookApplied, urgent: !hookApplied))
                    .help(selectedPlatform == .claudeCode
                        ? "Writes the UserPromptSubmit hook into ~/.claude/settings.json + the speak MCP server into ~/.claude.json. Re-applies cleanly on rebuild."
                        : selectedPlatform == .codexCLI
                        ? "Writes the speak MCP server + UserPromptSubmit hook into ~/.codex/config.toml (needs one-time hook trust). Re-applies cleanly on rebuild."
                        : selectedPlatform == .pi
                        ? "Copies the OpenWhisperer extension into ~/.pi/agent/extensions/ (no MCP). Run /reload in Pi afterward."
                        : "Writes the speak MCP server into ~/.gemini/config/mcp_config.json + the PreInvocation hook into ~/.gemini/config/hooks.json. Start a new agy session afterward.")
                }

                // Apply message feedback
                if !applyMessage.isEmpty {
                    Text(applyMessage)
                        .font(OWFont.caption())
                        .foregroundColor(
                            applyMessage.lowercased().contains("fail") ? OWColor.danger : OWColor.live
                        )
                        .transition(.opacity)
                }
                // (Removed the redundant "HOOK configured" diagnostic row —
                // the Applied pill above already conveys this state.)
            }
        }
        .onChange(of: setupExpanded) { _, newValue in
            if newValue {
                try? FileManager.default.removeItem(at: Paths.setupCardExpanded)
            } else {
                try? "closed".write(to: Paths.setupCardExpanded, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Server Card

    private var serverCard: some View {
        OWCollapsibleCard(
            title: "Server & Logs",
            icon: "gearshape",
            help: "The on-device text-to-speech server (local port 8000), downloaded models, and logs. Dictation runs separately from this.",
            expanded: $serverExpanded
        ) {
            EmptyView()
        } expandedContent: {
            VStack(alignment: .leading, spacing: 8) {
                // Model status rows (moved here from the top of the menu)
                VStack(spacing: 0) {
                    ModernStatusRow(
                        label: "Parakeet STT",
                        subtitle: dictationManager.sttModelReady
                            ? "parakeet-tdt-0.6b-v3"
                            : (dictationManager.sttStatus ?? "Loading…"),
                        port: "local",
                        status: dictationManager.sttModelReady ? .running : .starting
                    )
                    OWInternalDivider()
                    ModernStatusRow(
                        label: "Kokoro TTS",
                        subtitle: serverManager.ttsModel,
                        port: "\(serverManager.port)",
                        status: serverManager.status
                    )
                }
                OWInternalDivider()

                let serverStopped = serverManager.status == .stopped

                HStack(spacing: 6) {
                    if serverStopped || serverManager.status == .error {
                        Button(action: { serverManager.startAll() }) {
                            Label("Start Server", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OWRowButtonStyle())
                    } else {
                        Button(action: {
                            serverManager.stopAll()
                            showStoppedBanner = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showStoppedBanner = false
                            }
                        }) {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OWRowButtonStyle())
                    }

                    Button(action: {
                        // A SwiftUI `.alert` is hosted inside the MenuBarExtra(.window) popover,
                        // which resigns key and tears down on the first click — so the confirm
                        // could never complete. Present a standalone AppKit NSAlert instead
                        // (the app's existing pattern for windows; see ConfigManager.showLog).
                        let (lines, total) = ModelStorage.breakdown()
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "Delete downloaded models?"
                        alert.informativeText = total == 0
                            ? "No downloaded models were found — nothing to delete."
                            : "Frees \(ModelStorage.format(total)):\n\n"
                                + lines.joined(separator: "\n")
                                + "\n\nThe models re-download automatically the next time you dictate or use speech."
                        if total == 0 {
                            alert.addButton(withTitle: "OK")
                        } else {
                            alert.addButton(withTitle: "Delete")   // rightmost
                            alert.addButton(withTitle: "Cancel")
                            alert.buttons[0].keyEquivalent = ""     // don't let Return delete
                            alert.buttons[1].keyEquivalent = "\r"   // Cancel is the default
                        }
                        NSApp.activate(ignoringOtherApps: true)
                        if total > 0, alert.runModal() == .alertFirstButtonReturn {
                            serverManager.stopAll()
                            ModelStorage.deleteAll()
                            deletedModelsBanner = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { deletedModelsBanner = false }
                        }
                    }) {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OWRowButtonStyle())

                    PortField(label: "", port: $serverManager.port, disabled: !serverStopped)
                }

                if deletedModelsBanner {
                    Text("Models deleted — they'll re-download on next use")
                        .font(OWFont.body(11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity)
                }

                if showStoppedBanner {
                    Text("Server stopped")
                        .font(OWFont.body(11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity)
                }

                ModernDiagnosticRow(label: "Server reachable", ok: serverReachable)

                OWInternalDivider()

                HStack(spacing: 6) {
                    Button(action: { ConfigManager.showLog(name: "Server", url: Paths.serverLog) }) {
                        Label("Server Log", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OWRowButtonStyle())

                    Button(action: {
                        ConfigManager.showLog(
                            name: "Events",
                            url: Paths.appSupport.appendingPathComponent("paste_debug.log")
                        )
                    }) {
                        Label("Events Log", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OWRowButtonStyle())
                }

                Button(action: {
                    Diagnostics.copyToClipboard(dictation: dictationManager, server: serverManager)
                    diagnosticsCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { diagnosticsCopied = false }
                }) {
                    Label(diagnosticsCopied ? "Copied to clipboard" : "Copy Diagnostics",
                          systemImage: diagnosticsCopied ? "checkmark" : "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OWRowButtonStyle())

                OWInternalDivider()

                // Permissions — merged into Server & Logs (2026-07-19 request).
                OWCardHeader(title: allPermissionsGranted ? "Permissions" : "Permissions Required", icon: "lock.shield",
                             help: "macOS grants Open Whisperer needs: Accessibility (type into the focused app), Microphone (record dictation), and Speech Recognition (hands-free wake words). Tap a row to open Settings.")
                ModernDiagnosticRow(label: "Accessibility", ok: accessibilityManager.isGranted)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .help("Lets the app type dictated text into the focused app via keystrokes — the clipboard is never touched. Tap to open Settings.")
                ModernDiagnosticRow(label: "Microphone", ok: dictationManager.recorder.micPermission)
                    .contentShape(Rectangle())
                    .onTapGesture { dictationManager.recorder.openMicSettings() }
                    .help("Lets the app record your microphone to capture dictation. Tap to open Settings.")
                // Only relevant in hands-free — hidden otherwise so we don't nag for a
                // permission the current mode never uses.
                if selectedMode == .handsFree {
                    ModernDiagnosticRow(label: "Speech Recognition", ok: dictationManager.keywordDetector.permissionGranted)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .help("Hands-Free only: Apple Speech detects the wake words \"initiate\" and \"hold on\". Normal dictation doesn't use it. Tap to open Settings.")
                }
            }
        }
        .onChange(of: serverExpanded) { _, newValue in
            if newValue {
                try? "open".write(to: Paths.serverCardExpanded, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: Paths.serverCardExpanded)
            }
        }
    }

    // MARK: - Footer

    /// Speech Recognition is hands-free-only, so it counts toward "all granted" only in that
    /// mode — otherwise a hold-to-talk user who (correctly) never granted it would never read
    /// as fully granted. Drives the Permissions header title ("Permissions" vs. "…Required").
    private var allPermissionsGranted: Bool {
        let speechNeeded = selectedMode == .handsFree
        return accessibilityManager.isGranted
            && dictationManager.recorder.micPermission
            && (!speechNeeded || dictationManager.keywordDetector.permissionGranted)
    }

    private var footerSection: some View {
        OWCard {
            VStack(alignment: .leading, spacing: 8) {
                // Launch at login
                ModernDiagnosticRow(label: "Start on startup", ok: launchAtLogin)
                    .contentShape(Rectangle())
                    .onTapGesture { launchAtLogin.toggle() }
                    .onChange(of: launchAtLogin) { _, enabled in
                        let service = SMAppService.mainApp
                        do {
                            if enabled {
                                try service.register()
                            } else {
                                try service.unregister()
                            }
                        } catch {
                            NSLog("Login item toggle failed: \(error)")
                            DispatchQueue.main.async {
                                launchAtLogin = service.status == .enabled
                            }
                        }
                    }

                OWInternalDivider()

                HStack {
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .font(OWFont.caption())
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Label("Quit", systemImage: "power")
                            .font(OWFont.body(11))
                    }
                    .buttonStyle(OWRowButtonStyle())
                    .keyboardShortcut("q")
                }
            }
        }
    }

    // MARK: - Computed helpers

    private var stateColor: Color {
        switch dictationManager.recorderState {
        case .recording: return OWColor.recording
        case .uploading: return OWColor.warn
        case .listening: return OWColor.live
        case .idle: return dictationManager.ttsPlaying ? OWColor.accentDeep : OWColor.live
        }
    }

    /// The status dot glows for the "live" states (recording / listening / idle-ready),
    /// not for transient transcribing or while TTS is playing — derived from state, not
    /// from a fragile color comparison.
    private var stateGlows: Bool {
        switch dictationManager.recorderState {
        case .recording, .listening: return true
        case .uploading: return false
        case .idle: return !dictationManager.ttsPlaying
        }
    }

    private var stateLabel: String {
        if dictationManager.isCalibrating { return "Calibrating..." }
        if dictationManager.ttsPlaying { return "Playing..." }
        switch dictationManager.recorderState {
        case .recording: return "Recording..."
        case .uploading: return "Transcribing..."
        case .listening: return "Listening..."
        case .idle: return dictationManager.speakArmed ? "Standby · will speak" : "Standby"
        }
    }

    private func refreshDiagnostics() {
        hookApplied = ConfigManager.checkHookConfigured(for: selectedPlatform)
        // Re-read mic/speech authorization each time the menu opens so a revocation (or a
        // grant made in System Settings after launch) shows up without relaunching. Accessibility
        // has its own continuous poll. Speech only when hands-free — otherwise we'd re-request
        // (and could re-prompt) a permission that mode never uses.
        dictationManager.recorder.checkPermission()
        if selectedMode == .handsFree {
            dictationManager.keywordDetector.checkPermission()
        }
        ConfigManager.testTTS(port: serverManager.port) { ok in
            DispatchQueue.main.async { serverReachable = ok }
        }
    }

    private func saveFocusApp() {
        guard autoFocusEnabled, !focusAppName.isEmpty else { return }
        try? focusAppName.write(to: Paths.autoFocusApp, atomically: true, encoding: .utf8)
        // Owner-only — the target app name is read by the local server (T2.5)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.autoFocusApp.path)
    }

    private func debouncedSaveFocusApp() {
        saveDebounce?.cancel()
        let work = DispatchWorkItem { saveFocusApp() }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

