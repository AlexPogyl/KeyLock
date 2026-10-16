import Cocoa
import SwiftUI
import Combine
import Carbon.HIToolbox

/// Borderless panel that is still allowed to become key so the hotkey recorder
/// receives keystrokes normally.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let controller = LockController.shared

    private var statusItem: NSStatusItem!
    private var panel: KeyablePanel?
    private var hosting: NSHostingView<MenuView>?
    private var permissionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastPanelClose: CFTimeInterval = 0
    private var signalSources: [DispatchSourceSignal] = []
    private var backdropWindow: NSWindow?
    /// Demo/screenshot mode: keeps the panel on screen no matter what has focus.
    private var demoMode = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        controller.refreshPermissions()
        if controller.accessibilityGranted { _ = controller.installTapIfPossible() }

        setUpStatusItem()
        setUpPanel()
        observeController()
        startPermissionPolling()
        installSignalHandlers()
        applyStatusItemVisibility()

        let handled = handleSpecialLaunchModes()
        if !handled {
            // Launched by a human (Finder, Spotlight, `open`): show the menu right
            // away so the app is usable even with the menu bar icon switched off.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showPanel()
            }
        }
    }

    /// Spotlight / Finder / `open -a` while KeyLock is already running brings the
    /// menu back — this is the supported way to reach the app when the menu bar
    /// icon has been hidden in the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.performUnlock(reason: .quit)
        EventTap.shared.uninstall()
        TouchBarController.shared.unblock()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusImage(locked: false)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "KeyLock — блокировка клавиатуры и трекпада"
        }
    }

    private func statusImage(locked: Bool) -> NSImage? {
        let name = locked ? "lock.fill" : "lock.open"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "KeyLock")
        image?.isTemplate = true
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        togglePanel()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let locked = controller.isLocked
        let toggle = menu.addItem(withTitle: locked ? "Разблокировать" : "Заблокировать",
                                  action: #selector(contextToggleLock), keyEquivalent: "")
        toggle.target = self
        menu.addItem(.separator())
        let verify = menu.addItem(withTitle: "Проверить комбинацию разблокировки",
                                  action: #selector(contextVerify), keyEquivalent: "")
        verify.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти из KeyLock",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func contextToggleLock() { controller.toggleLock() }
    @objc private func contextVerify() { controller.beginVerification() }

    // MARK: - Panel

    private func setUpPanel() {
        let root = MenuView(controller: controller)
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        self.hosting = hosting

        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 348, height: 620),
                                 styleMask: [.borderless],
                                 backing: .buffered,
                                 defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true           // AppKit draws a shadow that follows the rounded shape
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hosting
        panel.delegate = self
        self.panel = panel

        NotificationCenter.default.addObserver(self, selector: #selector(panelResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: panel)
    }

    @objc private func panelResignedKey() {
        // Keep the panel around while a hotkey recording or verification is running.
        guard !controller.isVerifying, !demoMode else { return }
        hidePanel()
    }

    private func observeController() {
        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.synchronizePanel() }
            }
            .store(in: &cancellables)
    }

    private func applyStatusItemVisibility() {
        statusItem.isVisible = controller.showMenuBarIcon
    }

    /// Resizes the panel to the SwiftUI content and refreshes the status item icon.
    private func synchronizePanel() {
        applyStatusItemVisibility()
        if let button = statusItem.button {
            button.image = statusImage(locked: controller.isLocked)
        }
        guard let panel, let hosting, panel.isVisible else { return }
        resize(panel: panel, hosting: hosting, reposition: false)
    }

    private func resize(panel: NSPanel, hosting: NSView, reposition: Bool) {
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let size = NSSize(width: 348, height: max(200, fitting.height))
        if abs(panel.frame.height - size.height) > 0.5 || abs(panel.frame.width - size.width) > 0.5 {
            panel.setContentSize(size)
        }
        if reposition { position(panel) }
    }

    private func position(_ panel: NSPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main

        var x = buttonFrame.midX - panel.frame.width / 2
        let y = buttonFrame.minY - panel.frame.height - 8

        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: max(y, (screen?.visibleFrame.minY ?? 0) + 8)))
    }

    func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let panel, let hosting else { return }
        // Ignore the re-open that would otherwise follow the close caused by the
        // very same click on the status item.
        if CACurrentMediaTime() - lastPanelClose < 0.25, !panel.isVisible { return }

        controller.refreshPermissions()
        synchronizePanel()
        resize(panel: panel, hosting: hosting, reposition: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        guard let panel, panel.isVisible else { return }
        lastPanelClose = CACurrentMediaTime()
        panel.orderOut(nil)
    }

    // MARK: - Housekeeping

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let wasGranted = self.controller.accessibilityGranted
                self.controller.refreshPermissions()
                if !wasGranted, self.controller.accessibilityGranted {
                    self.controller.show(.init(kind: .success,
                                               text: "Разрешение получено. Теперь проверьте комбинацию разблокировки."))
                }
                // Safety net #1: permission revoked mid-lock must never leave the Mac
                // with a dead keyboard.
                if self.controller.isLocked, !self.controller.accessibilityGranted {
                    self.controller.performUnlock(reason: .emergency)
                }
                // Safety net #2: while another process holds "secure input" (password
                // prompts, some terminals) the system stops delivering key events to
                // event taps — which means the unlock combination can no longer be
                // seen. Release the block instead of risking a stuck keyboard.
                if self.controller.isLocked, IsSecureEventInputEnabled() {
                    self.controller.show(.init(kind: .warning,
                                               text: "Разблокировано: активно «Безопасный ввод», перехват клавиш невозможен"))
                    self.controller.performUnlock(reason: .emergency)
                }
            }
        }
    }

    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.controller.performUnlock(reason: .quit)
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Demo / screenshot helpers

    @discardableResult
    private func handleSpecialLaunchModes() -> Bool {
        let args = CommandLine.arguments

        if args.contains("--selftest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                SelfTest.run(controller: self.controller)
            }
            return true
        }

        if args.contains("--headless") { return true }

        guard args.contains("--demo") else { return false }
        demoMode = true

        func value(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return args[index + 1]
        }

        if let state = value("--state") {
            // Screenshots should show a representative configuration.
            controller.blockKeyboard = true
            controller.blockTrackpad = true
            controller.blockTouchBar = true
            controller.autoUnlockMinutes = 0
            controller.unlockOnWake = true
            switch state {
            case "verified":
                controller.forceVerifiedForDemo()
            case "locked":
                controller.forceVerifiedForDemo()
                controller.forceLockedForDemo()
            case "advanced":
                controller.forceVerifiedForDemo()
                controller.showAdvanced = true
            case "blocked-keyboard":
                controller.blockTrackpad = false
                controller.blockTouchBar = false
            default:
                break
            }
        }

        if args.contains("--backdrop") { showDemoBackdrop() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showPanel()
        }
        return true
    }

    /// Full-screen colourful backdrop placed just under the panel so the glass has
    /// something to blur. Only used while taking screenshots.
    private func showDemoBackdrop() {
        guard let screen = NSScreen.main else { return }
        let window = NSWindow(contentRect: screen.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .normal
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: DemoWallpaper())
        window.orderFrontRegardless()
        backdropWindow = window
    }
}
