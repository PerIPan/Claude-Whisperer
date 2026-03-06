import Foundation

enum Paths {
    /// ~/Library/Application Support/ClaudeWhisperer
    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ClaudeWhisperer")
    }()

    /// Python venv location
    static let venv = appSupport.appendingPathComponent("venv")

    /// Python binary inside venv
    static let python = venv.appendingPathComponent("bin/python")

    /// uv binary (bundled in app Resources)
    static var uvBinary: URL {
        Bundle.main.resourceURL!.appendingPathComponent("uv")
    }

    /// Bundled server scripts
    static var whisperServer: URL {
        Bundle.main.resourceURL!.appendingPathComponent("servers/whisper_server.py")
    }

    /// Bundled hook script
    static var ttsHook: URL {
        Bundle.main.resourceURL!.appendingPathComponent("hooks/tts-hook.sh")
    }

    /// Bundled speak script
    static var speakScript: URL {
        Bundle.main.resourceURL!.appendingPathComponent("scripts/speak.sh")
    }

    /// Setup marker file
    static let setupComplete = appSupport.appendingPathComponent(".setup-complete")

    /// Server PID files
    static let sttPidFile = appSupport.appendingPathComponent("whisper.pid")
    static let ttsPidFile = appSupport.appendingPathComponent("tts.pid")

    /// Log files
    static let sttLog = appSupport.appendingPathComponent("whisper.log")
    static let ttsLog = appSupport.appendingPathComponent("tts.log")
    static let setupLog = appSupport.appendingPathComponent("setup.log")

    /// Claude Code settings
    static let claudeSettings: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }()

    /// Ensure directories exist
    static func ensureDirectories() {
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }
}
