import AppKit
import SwiftUI

@main
struct ClipboardRefinerApp: App {
    var body: some Scene {
        WindowGroup("Post Enhancer") {
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
