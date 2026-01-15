import SwiftUI
import AppKit

/// Main app entry point
@main
struct MontrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window
        Settings {
            SettingsView()
        }
    }
}
