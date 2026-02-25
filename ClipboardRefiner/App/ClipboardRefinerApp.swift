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
            .frame(minWidth: 820, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        Settings {
            SettingsView()
        }
    }
}
