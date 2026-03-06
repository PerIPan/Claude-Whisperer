import SwiftUI

@main
struct ClaudeWhispererApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Claude Whisperer", systemImage: "waveform") {
            MenuBarView()
                .environmentObject(appDelegate.serverManager)
                .environmentObject(appDelegate.setupManager)
        }
        .menuBarExtraStyle(.window)
    }
}
