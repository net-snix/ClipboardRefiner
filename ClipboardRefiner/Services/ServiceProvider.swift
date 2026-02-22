import AppKit
import Foundation

@objc final class ServiceProvider: NSObject {

    @objc func openClipboardRefiner(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text selected" as NSString
            return
        }

        let resolvedAction: String
        switch userData?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "explain":
            resolvedAction = "explain"
        default:
            resolvedAction = "rewrite"
        }

        AppLogger.shared.info("Clipboard Refiner service invoked (open menu bar): \(resolvedAction)")

        DispatchQueue.main.async {
            guard let delegate = AppDelegate.shared else {
                AppLogger.shared.error("Unable to open menu bar: missing AppDelegate instance")
                return
            }

            delegate.openMenuBar(withPrefilledText: text, action: resolvedAction)
        }
    }

    @objc func rewriteInteractive(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text selected" as NSString
            return
        }

        AppLogger.shared.info("Interactive rewrite service invoked")

        DispatchQueue.main.async {
            let controller = PopupWindowController.shared
            controller.show(
                originalText: text,
                style: SettingsManager.shared.defaultStyle
            ) { result in
                switch result {
                case .replace(let newText):
                    pboard.clearContents()
                    pboard.setString(newText, forType: .string)

                case .copy(let newText):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(newText, forType: .string)

                case .cancel:
                    break
                }

                NSApp.stopModal()
            }

            NSApp.runModal(for: controller.window!)
        }
    }

    @objc func rewriteQuick(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text selected" as NSString
            return
        }

        let style = RewriteStyle.from(userData: userData)

        AppLogger.shared.info("Quick rewrite service invoked with style: \(style.rawValue)")

        if SettingsManager.shared.quickBehavior == .interactive {
            rewriteInteractive(pboard, userData: userData, error: error)
            return
        }

        RewriteEngine.shared.rewriteForService(text: text, style: style) { result in
            switch result {
            case .success(let rewrittenText):
                pboard.clearContents()
                pboard.setString(rewrittenText, forType: .string)

            case .failure(let llmError):
                AppLogger.shared.error("Quick rewrite failed: \(llmError.localizedDescription)")
            }
        }
    }
}
