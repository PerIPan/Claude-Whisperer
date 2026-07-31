import SwiftUI
import OpenWhispererKit

/// Spoken replies (TTS output only): which voice, how fast/loud, how much, and when.
struct VoiceTab: View {
    @State private var selectedVoice = "af_heart"
    @State private var selectedSpeed: Double = Double(TTSSpeed.default)
    @State private var selectedVolume: Double = 1.0
    @State private var selectedStyle = "normal"
    @State private var selectedResponse = "voice"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OWCard {
                VStack(alignment: .leading, spacing: 10) {
                    OWCardHeader(title: "Sound", icon: "speaker.wave.2.fill",
                                 help: "The voice that reads replies aloud, and how fast and loud it speaks. Non-default voices download on first use.")

                    OWPickerRow(label: "Voice", labelWidth: 62) {
                        OWGroupedMenuPicker(selection: $selectedVoice, groups: SettingsData.voiceGroups)
                            .frame(maxWidth: .infinity)
                    }
                    .onChange(of: selectedVoice) { _, newValue in
                        try? newValue.write(to: Paths.ttsVoice, atomically: true, encoding: .utf8)
                    }

                    OWInternalDivider()

                    OWPickerRow(label: "Speed", labelWidth: 62) {
                        HStack(spacing: 8) {
                            // Bounds MUST equal TTSSpeed.min/max (see TTSSpeed.swift).
                            // Writes once on release, not on every 0.05 step.
                            OWSlider(value: $selectedSpeed, range: 0.7...1.5) {
                                try? String(format: "%.2f", selectedSpeed)
                                    .write(to: Paths.ttsSpeed, atomically: true, encoding: .utf8)
                            }
                            .help("How fast replies are read aloud. 1× is the default Kokoro rate.")
                            Text(SettingsData.multiplierLabel(selectedSpeed))
                                .font(OWFont.body(11))
                                .foregroundColor(OWColor.inkSoft)
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    OWPickerRow(label: "Volume", labelWidth: 62) {
                        HStack(spacing: 8) {
                            // Bounds MUST equal TTSVolume.min/max (see TTSVolume.swift).
                            OWSlider(value: $selectedVolume, range: 0.3...2.0) {
                                try? String(format: "%.2f", selectedVolume)
                                    .write(to: Paths.ttsVolume, atomically: true, encoding: .utf8)
                            }
                            .help("How loud replies are read aloud. 1× is normal; higher may clip.")
                            Text(SettingsData.multiplierLabel(selectedVolume))
                                .font(OWFont.body(11))
                                .foregroundColor(OWColor.inkSoft)
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            OWCard {
                VStack(alignment: .leading, spacing: 10) {
                    OWCardHeader(title: "Response", icon: "text.bubble",
                                 help: """
                                 How much of a reply is spoken, and on which turns.

                                 Length — Terse: one short sentence. Normal: one sentence. \
                                 Rich: a sentence or two. Full: a spoken paragraph that \
                                 explains the reasoning, not just the outcome.

                                 Speak — Only when I dictate: typed turns stay silent. \
                                 On every turn: every reply is spoken. Only when I'm needed: \
                                 speaks only when the turn ends on you — a question, a blocked \
                                 step, an approval, or a failure — and stays silent when work \
                                 simply succeeded.
                                 """)

                    OWPickerRow(label: "Length", labelWidth: 62) {
                        OWMenuPicker(selection: $selectedStyle, options: SettingsData.styleLevels)
                            .frame(maxWidth: .infinity)
                    }
                    .onChange(of: selectedStyle) { _, newValue in
                        try? newValue.write(to: Paths.ttsStyle, atomically: true, encoding: .utf8)
                    }

                    // Self-describing options — the explanatory caption is no longer needed.
                    OWPickerRow(label: "Speak", labelWidth: 62) {
                        OWMenuPicker(selection: $selectedResponse, options: SettingsData.responseModes)
                            .frame(maxWidth: .infinity)
                    }
                    .onChange(of: selectedResponse) { _, newValue in
                        try? newValue.write(to: Paths.ttsResponseMode, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        selectedVolume = Double(TTSVolume.parse(try? String(contentsOf: Paths.ttsVolume, encoding: .utf8)))
        selectedSpeed = Double(TTSSpeed.parse(try? String(contentsOf: Paths.ttsSpeed, encoding: .utf8)))
        if let savedVoice = try? String(contentsOf: Paths.ttsVoice, encoding: .utf8),
           !savedVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let voice = savedVoice.trimmingCharacters(in: .whitespacesAndNewlines)
            if SettingsData.allVoices.contains(where: { $0.id == voice }) { selectedVoice = voice }
        }
        if let savedStyle = try? String(contentsOf: Paths.ttsStyle, encoding: .utf8) {
            let style = savedStyle.trimmingCharacters(in: .whitespacesAndNewlines)
            // "full" is a real tier again (2.0.0), so it no longer maps onto "rich" —
            // a stored legacy value now selects the tier it always named.
            if SettingsData.styleLevels.contains(where: { $0.id == style }) {
                selectedStyle = style
            }
        }
        if let savedMode = try? String(contentsOf: Paths.ttsResponseMode, encoding: .utf8) {
            let mode = savedMode.trimmingCharacters(in: .whitespacesAndNewlines)
            if SettingsData.responseModes.contains(where: { $0.id == mode }) { selectedResponse = mode }
        }
    }
}
