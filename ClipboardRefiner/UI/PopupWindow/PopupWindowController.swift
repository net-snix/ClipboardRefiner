import AppKit
import SwiftUI

enum PopupResult {
    case replace(String)
    case copy(String)
    case cancel
}

final class PopupWindowController: NSObject {
    static let shared = PopupWindowController()

    private(set) var window: NSPanel?
    private var hostingView: NSHostingView<PopupView>?
    private var viewModel: PopupViewModel?
    private var completion: ((PopupResult) -> Void)?

    private override init() {
        super.init()
    }

    func show(
        originalText: String,
        style: RewriteStyle,
        completion: @escaping (PopupResult) -> Void
    ) {
        self.completion = completion

        let viewModel = PopupViewModel(
            originalText: originalText,
            initialStyle: style
        )
        viewModel.onComplete = { [weak self] result in
            self?.handleResult(result)
        }
        self.viewModel = viewModel

        let popupView = PopupView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: popupView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        self.hostingView = hostingView

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Rewrite with GPT-5"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView
        panel.center()
        panel.delegate = self

        panel.minSize = NSSize(width: 400, height: 300)
        panel.maxSize = NSSize(width: 800, height: 600)

        self.window = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            viewModel.startRewrite()
        }
    }

    private func handleResult(_ result: PopupResult) {
        window?.orderOut(nil)
        completion?(result)
        cleanup()
    }

    private func cleanup() {
        viewModel?.cleanup()
        viewModel = nil
        hostingView = nil
        window = nil
        completion = nil
    }
}

extension PopupWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        handleResult(.cancel)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        handleResult(.cancel)
        return true
    }
}
