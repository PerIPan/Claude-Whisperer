import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let serverManager = ServerManager()
    let setupManager = SetupManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menubar-only app)
        NSApp.setActivationPolicy(.accessory)

        if setupManager.isSetupComplete {
            serverManager.startAll()
        } else {
            setupManager.runFirstLaunchSetup { [weak self] success in
                if success {
                    self?.serverManager.startAll()
                    // Show setup instructions on first launch
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        ConfigManager.showClaudeHookInstructions()
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        serverManager.stopAll()
    }
}
