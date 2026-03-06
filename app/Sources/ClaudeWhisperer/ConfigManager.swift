import Foundation
import SwiftUI

enum ConfigManager {

    // MARK: - Claude Code Hook Instructions

    static func showClaudeHookInstructions() {
        let hookPath = Paths.ttsHook.path
        let window = InstructionWindow(
            title: "Configure Claude Code Hook",
            instructions: """
            Add this to your Claude Code settings:

            1. Open ~/.claude/settings.json (or project .claude/settings.json)
            2. Add the following under "hooks":

            {
              "hooks": {
                "Stop": [{
                  "hooks": [{
                    "type": "command",
                    "command": "\(hookPath)",
                    "timeout": 60
                  }]
                }]
              }
            }

            3. Also add the [VOICE: ...] instruction to your project's CLAUDE.md:

            ALWAYS include a [VOICE: ...] tag at the END of every response.
            This tag contains a short spoken summary that TTS reads aloud.
            """
        )
        window.show()
    }

    // MARK: - Voquill Instructions

    static func showVoquillInstructions() {
        let window = InstructionWindow(
            title: "Configure Voquill",
            instructions: """
            Set up Voquill to use your local Whisper server:

            1. Open Voquill settings
            2. Select "OpenAI Compatible API" mode
            3. Set these values:

               Endpoint:  http://localhost:8000
               Model:     whisper-1
               API Key:   any-value (required but not checked)
               Language:  en

            4. Make sure the Whisper server is running (green dot in menubar)

            Voquill will now use your local Whisper for
            high-accuracy, private transcription.
            """
        )
        window.show()
    }
    // MARK: - Voquill Download

    static func showVoquillDownload() {
        let window = InstructionWindow(
            title: "Get Voquill",
            instructions: """
            Voquill is a free, open-source macOS dictation app
            that works with your local Whisper server.

            Download from GitHub:
            https://github.com/nicobailey/Voquill

            1. Go to the Releases page
            2. Download the latest .dmg
            3. Drag Voquill to Applications
            4. Then use "Voquill Setup" in the menubar
               to configure it for local Whisper
            """
        )
        window.show()
    }

    // MARK: - View Logs

    static func showLogs() {
        let logFiles: [(String, URL)] = [
            ("Whisper STT", Paths.sttLog),
            ("Kokoro TTS", Paths.ttsLog),
            ("Setup", Paths.setupLog)
        ]

        var combined = ""
        for (name, url) in logFiles {
            combined += "=== \(name) Log ===\n"
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                // Show last 50 lines
                let lines = content.components(separatedBy: "\n")
                let tail = lines.suffix(50).joined(separator: "\n")
                combined += tail.isEmpty ? "(empty)\n" : tail + "\n"
            } else {
                combined += "(no log file yet)\n"
            }
            combined += "\n"
        }

        let window = InstructionWindow(
            title: "Server Logs",
            instructions: combined
        )
        window.show()
    }
}

// MARK: - Instruction Window

class InstructionWindow: NSObject, NSWindowDelegate {
    private let title: String
    private let instructions: String
    private var window: NSWindow?

    // Keep alive until window closes
    private static var activeWindows: [InstructionWindow] = []

    init(title: String, instructions: String) {
        self.title = title
        self.instructions = instructions
    }

    func show() {
        InstructionWindow.activeWindows.append(self)

        DispatchQueue.main.async { [self] in
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = title
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self

            let hostingView = NSHostingView(rootView: InstructionView(
                title: title,
                instructions: instructions
            ))
            w.contentView = hostingView
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            self.window = w
        }
    }

    func windowWillClose(_ notification: Notification) {
        InstructionWindow.activeWindows.removeAll { $0 === self }
    }
}

struct InstructionView: View {
    let title: String
    let instructions: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(instructions)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }

            HStack {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(instructions, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }) {
                    Label(copied ? "Copied!" : "Copy to Clipboard", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Spacer()
            }
        }
        .padding(16)
    }
}
