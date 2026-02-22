import AppKit
import SwiftUI

extension Notification.Name {
    static let clipboardRefinerMenuPopoverDidShow = Notification.Name("ClipboardRefiner.menuPopoverDidShow")
    static let clipboardRefinerMenuPrefillText = Notification.Name("ClipboardRefiner.menuPrefillText")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private var serviceProvider: ServiceProvider?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var onboardingWindow: NSWindow?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    override init() {
        super.init()
        Self.shared = self
    }

    func openMenuBar(withPrefilledText text: String, action: String = "rewrite") {
        let openAction = { [weak self] in
            guard let self else { return }

            setupMenuBar()

            if self.popover.isShown {
                NSApp.activate(ignoringOtherApps: true)
            } else {
                self.showPopover(nil, shouldActivate: true)
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .clipboardRefinerMenuPrefillText,
                    object: nil,
                    userInfo: ["text": text, "action": action]
                )
            }
        }

        if Thread.isMainThread {
            openAction()
        } else {
            DispatchQueue.main.async(execute: openAction)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupServices()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceDidActivateApp),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        AppLogger.shared.info("Clipboard Refiner launched")

        if !SettingsManager.shared.hasSeenOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showOnboarding()
            }
        } else if !SettingsManager.shared.hasAPIKey(for: SettingsManager.shared.selectedProvider) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.shared.info("Clipboard Refiner terminating")
    }

    @objc private func handleAppDidResignActive(_ notification: Notification) {
        if popover?.isShown == true {
            popover.performClose(nil)
        }
    }

    @objc private func handleWorkspaceDidActivateApp(_ notification: Notification) {
        guard popover?.isShown == true else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            popover.performClose(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func setupMenuBar() {
        if statusItem != nil, popover != nil {
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Clipboard Refiner")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self

        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                onDismiss: { [weak self] in
                    self?.popover.performClose(nil)
                }
            )
        )
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender, shouldActivate: false)
        }
    }

    private func showPopover(_ sender: AnyObject?, shouldActivate: Bool) {
        guard let button = statusItem.button else { return }
        
        NSApp.setActivationPolicy(.accessory)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startOutsideClickMonitoring()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipboardRefinerMenuPopoverDidShow, object: nil)
        }
        button.highlight(true)
        if shouldActivate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func repositionPopover() {
        guard let popover,
              popover.isShown,
              let statusItem,
              let button = statusItem.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
    }

    private func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }

    private func updateActivationPolicy() {
        let hasSettings = settingsWindow != nil
        let isMenuVisible = popover.isShown
        AppLogger.shared.info("Updating activation policy. Settings: \(hasSettings), Menu: \(isMenuVisible)")
        
        if hasSettings || isMenuVisible {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.closePopoverIfOutside(event: event)
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.closePopoverIfOutside(event: event)
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func closePopoverIfOutside(event: NSEvent?) {
        guard popover?.isShown == true else { return }
        guard let popoverWindow = popover.contentViewController?.view.window else {
            popover.performClose(nil)
            return
        }
        if let eventWindow = event?.window,
           isStatusBarClick(eventWindow: eventWindow, screenPoint: screenPointForEvent(event)) {
            return
        }
        if let eventWindow = event?.window, eventWindow == popoverWindow {
            return
        }

        let screenPoint = screenPointForEvent(event)
        if !popoverWindow.frame.contains(screenPoint) {
            popover.performClose(nil)
        }
    }

    private func isStatusBarClick(eventWindow: NSWindow, screenPoint: CGPoint) -> Bool {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              eventWindow == buttonWindow else {
            return false
        }

        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        return buttonFrameInScreen.contains(screenPoint)
    }

    private func screenPointForEvent(_ event: NSEvent?) -> CGPoint {
        if let event, let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return NSEvent.mouseLocation
    }

    private func setupServices() {
        serviceProvider = ServiceProvider()
        NSApp.servicesProvider = serviceProvider

        NSUpdateDynamicServices()

        AppLogger.shared.info("Services provider registered")
    }

    func showSettings() {
        AppLogger.shared.info("Showing settings window")
        NSApp.setActivationPolicy(.accessory)

        if let window = settingsWindow {
            AppLogger.shared.info("Settings window already exists, ordering front")
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            return
        }

        AppLogger.shared.info("Creating new settings window")
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Clipboard Refiner Settings"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        AppLogger.shared.info("Settings window created and ordered front")
        
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func showOnboarding() {
        guard let screen = NSScreen.main,
              let button = statusItem.button,
              let buttonWindow = button.window else {
            return
        }

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))

        let onboardingView = OnboardingArrowView(
            statusItemFrame: buttonRect,
            onDismiss: { [weak self] in
                self?.dismissOnboarding()
            }
        )

        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = hostingController
        window.ignoresMouseEvents = false

        onboardingWindow = window
        window.orderFrontRegardless()
    }

    private func dismissOnboarding() {
        SettingsManager.shared.hasSeenOnboarding = true
        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil

        if !SettingsManager.shared.hasAPIKey(for: SettingsManager.shared.selectedProvider) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showSettings()
            }
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            AppLogger.shared.info("Settings window closing")
            settingsWindow = nil
            updateActivationPolicy()
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        stopOutsideClickMonitoring()
        updateActivationPolicy()
    }
    
    func popoverDidDetach(_ popover: NSPopover) {
        statusItem.button?.highlight(false)
    }
}
