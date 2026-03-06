import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var setupManager: SetupManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                Text("Claude Whisperer")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            Divider()

            // Setup in progress
            if case .inProgress(let step) = setupManager.state {
                VStack(alignment: .leading, spacing: 4) {
                    Text(step)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: setupManager.progress)
                        .progressViewStyle(.linear)
                }
                .padding(.vertical, 4)
            } else if case .failed(let reason) = setupManager.state {
                VStack(alignment: .leading, spacing: 4) {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry Setup") {
                        setupManager.resetAndRerun { success in
                            if success { serverManager.startAll() }
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                // Server status
                StatusRow(label: "Whisper STT", port: "8000", status: serverManager.sttStatus)
                StatusRow(label: "Kokoro TTS", port: "8100", status: serverManager.ttsStatus)
            }

            Divider()

            // Controls
            if serverManager.sttStatus == .stopped && serverManager.ttsStatus == .stopped {
                Button(action: { serverManager.startAll() }) {
                    Label("Start Servers", systemImage: "play.circle")
                }
            } else {
                Button(action: { serverManager.stopAll() }) {
                    Label("Stop Servers", systemImage: "stop.circle")
                }
                Button(action: { serverManager.restartAll() }) {
                    Label("Restart Servers", systemImage: "arrow.clockwise")
                }
            }

            Divider()

            // Config actions
            Button(action: { ConfigManager.showClaudeHookInstructions() }) {
                Label("Claude Hook Setup", systemImage: "terminal")
            }

            Button(action: { ConfigManager.showVoquillInstructions() }) {
                Label("Voquill Setup", systemImage: "mic")
            }

            Button(action: { ConfigManager.showVoquillDownload() }) {
                Label("Get Voquill", systemImage: "arrow.down.circle")
            }

            Button(action: { ConfigManager.showLogs() }) {
                Label("View Logs", systemImage: "doc.text")
            }

            Divider()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 240)
    }

}

struct StatusRow: View {
    let label: String
    let port: String
    let status: ServerManager.ServerStatus

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(.body, design: .default))
            Spacer()
            Text(":\(port)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        switch status {
        case .running: return .green
        case .starting: return .orange
        case .error: return .red
        case .stopped: return .gray
        }
    }
}
