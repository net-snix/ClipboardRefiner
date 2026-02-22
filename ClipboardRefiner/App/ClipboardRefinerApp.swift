import AppKit
import SwiftUI

@main
struct ClipboardRefinerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Clipboard Refiner") {
            MenuBarView(
                onDismiss: {
                    NSApp.keyWindow?.close()
                }
            )
            .frame(minWidth: 760, minHeight: 700)
        }

        Settings {
            SettingsView()
        }
    }
}
