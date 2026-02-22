import AppIntents
import AppKit

enum RewriteStyleAppEnum: String, AppEnum {
    case rewrite
    case shorter
    case formal
    case casual
    case lessCringe
    case xComReach
    case promptEnhance

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Rewrite Style"

    static var caseDisplayRepresentations: [RewriteStyleAppEnum: DisplayRepresentation] = [
        .rewrite: "Rewrite",
        .shorter: "Shorter",
        .formal: "More Formal",
        .casual: "More Casual",
        .lessCringe: "Less Cringe",
        .xComReach: "Enhance X post",
        .promptEnhance: "Enhance AI prompt"
    ]

    var toRewriteStyle: RewriteStyle {
        switch self {
        case .rewrite: return .rewrite
        case .shorter: return .shorter
        case .formal: return .formal
        case .casual: return .casual
        case .lessCringe: return .lessCringe
        case .xComReach: return .xComReach
        case .promptEnhance: return .promptEnhance
        }
    }
}

struct RewriteClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Rewrite Clipboard"
    static var description = IntentDescription("Rewrites the current clipboard content using AI")

    @Parameter(title: "Style", default: .rewrite)
    var style: RewriteStyleAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Rewrite clipboard with \(\.$style)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.isEmpty else {
            throw RewriteClipboardError.emptyClipboard
        }

        let result = await withCheckedContinuation { continuation in
            let options = RewriteOptions(
                style: style.toRewriteStyle,
                aggressiveness: SettingsManager.shared.aggressiveness,
                streaming: false
            )

            RewriteEngine.shared.rewrite(
                text: clipboardText,
                options: options,
                streamHandler: { _ in },
                completion: { result in
                    continuation.resume(returning: result)
                }
            )
        }

        switch result {
        case .success(let rewrittenText):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rewrittenText, forType: .string)
            return .result(value: rewrittenText)

        case .failure(let error):
            throw RewriteClipboardError.rewriteFailed(error.localizedDescription)
        }
    }
}

@available(macOS 13.0, *)
enum RewriteClipboardError: Error, LocalizedError {
    case emptyClipboard
    case rewriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return "The clipboard is empty or does not contain text."
        case .rewriteFailed(let message):
            return "Rewrite failed: \(message)"
        }
    }
}

@available(macOS 13.0, *)
struct ClipboardRefinerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RewriteClipboardIntent(),
            phrases: [
                "Rewrite clipboard with \(.applicationName)",
                "Refine clipboard with \(.applicationName)",
                "Rewrite my clipboard with \(.applicationName)",
                "Make clipboard shorter with \(.applicationName)",
                "Make clipboard more formal with \(.applicationName)"
            ],
            shortTitle: "Rewrite Clipboard",
            systemImageName: "doc.on.clipboard"
        )
    }
}
