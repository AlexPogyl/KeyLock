import Cocoa
import Combine
import SwiftUI

/// Single source of truth for the app: settings, verification state, countdown and
/// the actual lock/unlock transitions.
@MainActor
final class LockController: ObservableObject {

    static let shared = LockController()

    // MARK: - Persisted settings

    @Published var blockKeyboard: Bool { didSet { save() } }
    @Published var blockTrackpad: Bool { didSet { save() } }
    @Published var blockTouchBar: Bool { didSet { save() } }
    @Published var showMenuBarIcon: Bool { didSet { save() } }
    @Published var unlockCombo: KeyCombo {
        didSet {
            // A new combination is unverified until the user proves it again.
            if unlockCombo != oldValue { comboVerified = false }
            EventTap.shared.unlockCombo = unlockCombo
            save()
        }
    }
    @Published var autoUnlockMinutes: Int { didSet { save(); restartAutoUnlockTimer() } }
    @Published var unlockOnWake: Bool { didSet { save() } }

    // MARK: - Runtime state

    @Published private(set) var isLocked = false
    @Published private(set) var comboVerified = false
    @Published private(set) var isVerifying = false
    @Published private(set) var countdown: Int?
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var tapInstalled = false
    @Published var notice: Notice?
    @Published private(set) var pointerFallbackActive = false
    /// Disclosure state for the "Дополнительно" section.
    @Published var showAdvanced = false

    struct Notice: Identifiable, Equatable {
        enum Kind { case info, warning, success, error }
        let id = UUID()
        var kind: Kind
        var text: String
    }

    private var countdownTimer: Timer?
    private var autoUnlockTimer: Timer?
    private var defaults = UserDefaults.standard

    private enum Key {
        static let blockKeyboard = "blockKeyboard"
        static let blockTrackpad = "blockTrackpad"
        static let blockTouchBar = "blockTouchBar"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let comboKeyCode = "unlockKeyCode"
        static let comboMods = "unlockMods"
        static let comboVerified = "comboVerified"
        static let autoUnlock = "autoUnlockMinutes"
        static let unlockOnWake = "unlockOnWake"
    }

    private init() {
        blockKeyboard = defaults.object(forKey: Key.blockKeyboard) as? Bool ?? true
        blockTrackpad = defaults.object(forKey: Key.blockTrackpad) as? Bool ?? true
        blockTouchBar = defaults.object(forKey: Key.blockTouchBar) as? Bool ?? false
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        let code = defaults.object(forKey: Key.comboKeyCode) as? Int
        let mods = defaults.object(forKey: Key.comboMods) as? [String]
        if let code, let mods {
            unlockCombo = KeyCombo(keyCode: UInt16(code),
                                   mods: Set(mods.compactMap { Mod(rawValue: $0) }))
        } else {
            unlockCombo = .default
        }
        autoUnlockMinutes = defaults.object(forKey: Key.autoUnlock) as? Int ?? 0
        unlockOnWake = defaults.object(forKey: Key.unlockOnWake) as? Bool ?? true
        // `comboVerified` is deliberately *not* restored: the unlock combination
        // has to be proven again in every session before anything can be blocked.
        comboVerified = false

        KeyCodeTranslator.shared.refreshLayout()
        EventTap.shared.unlockCombo = unlockCombo
        wireEventTap()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    // MARK: - Wiring

    private func wireEventTap() {
        let tap = EventTap.shared
        tap.onUnlock = { [weak self] in
            Task { @MainActor in self?.performUnlock(reason: .combination) }
        }
        tap.onComboCaptured = { [weak self] in
            Task { @MainActor in self?.finishVerification(success: true) }
        }
        tap.onAbort = { [weak self] in
            Task { @MainActor in self?.abortCountdown() }
        }
    }

    // MARK: - Persistence

    private func save() {
        defaults.set(blockKeyboard, forKey: Key.blockKeyboard)
        defaults.set(blockTrackpad, forKey: Key.blockTrackpad)
        defaults.set(blockTouchBar, forKey: Key.blockTouchBar)
        defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon)
        defaults.set(Int(unlockCombo.keyCode), forKey: Key.comboKeyCode)
        defaults.set(unlockCombo.mods.map(\.rawValue), forKey: Key.comboMods)
        defaults.set(autoUnlockMinutes, forKey: Key.autoUnlock)
        defaults.set(unlockOnWake, forKey: Key.unlockOnWake)
    }

    // MARK: - Permissions

    func refreshPermissions() {
        let granted = Permissions.isAccessibilityGranted
        if granted != accessibilityGranted { accessibilityGranted = granted }
        if granted, !EventTap.shared.isInstalled {
            EventTap.shared.install()
        }
        tapInstalled = EventTap.shared.isInstalled
    }

    func requestAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
        show(.init(kind: .info,
                   text: "Включите KeyLock в разделе «Универсальный доступ», затем вернитесь сюда."))
    }

    func installTapIfPossible() -> Bool {
        refreshPermissions()
        guard accessibilityGranted else { return false }
        let ok = EventTap.shared.install()
        tapInstalled = EventTap.shared.isInstalled
        return ok
    }

    // MARK: - Verification (the mandatory first step)

    /// Starts a global capture. The user is asked to press the combination.
    /// Nothing is blocked during this test — it only proves the key reaches us.
    func beginVerification() {
        guard unlockCombo.isUsable else {
            show(.init(kind: .warning, text: unlockCombo.validationMessage ?? "Комбинация не подходит"))
            return
        }
        guard installTapIfPossible() else {
            show(.init(kind: .warning, text: "Нужно разрешение «Универсальный доступ»"))
            requestAccessibility()
            return
        }
        isVerifying = true
        EventTap.shared.setMode(.capture)
        show(.init(kind: .info, text: "Нажмите \(unlockCombo.display) — можно прямо сейчас, меню закрывать не обязательно"))
        // Safety: never leave the app stuck in capture mode.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.isVerifying else { return }
            self.finishVerification(success: false)
        }
    }

    func cancelVerification() {
        guard isVerifying else { return }
        EventTap.shared.setMode(.idle)
        isVerifying = false
    }

    private func finishVerification(success: Bool) {
        isVerifying = false
        EventTap.shared.setMode(.idle)
        comboVerified = success
        save()
        show(success
             ? .init(kind: .success, text: "Комбинация \(unlockCombo.display) подтверждена — блокировку можно включать")
             : .init(kind: .warning, text: "Комбинация не сработала. Проверьте раскладку и попробуйте снова"))
        if success {
            HUD.shared.show(symbol: "checkmark.shield.fill",
                            title: "Комбинация работает",
                            subtitle: unlockCombo.display,
                            tint: .systemGreen,
                            duration: 1.6)
        }
    }

    // MARK: - Locking

    /// Validates everything and then runs the 3‑2‑1 countdown.
    func requestLock() {
        guard !isLocked else { return }
        guard blockKeyboard || blockTrackpad else {
            show(.init(kind: .warning, text: "Выберите, что блокировать: клавиатуру и/или трекпад"))
            return
        }
        guard unlockCombo.isUsable else {
            show(.init(kind: .warning, text: unlockCombo.validationMessage ?? "Комбинация не подходит"))
            return
        }
        guard comboVerified else {
            show(.init(kind: .warning, text: "Сначала проверьте разблокировку кнопкой «Проверить комбинацию»"))
            return
        }
        guard installTapIfPossible(), EventTap.shared.isEnabled else {
            show(.init(kind: .error, text: "Не удалось включить перехват ввода. Разрешите «Универсальный доступ» и повторите"))
            requestAccessibility()
            return
        }

        countdown = 3
        EventTap.shared.setMode(.arming)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let next = (self.countdown ?? 1) - 1
                if next <= 0 {
                    timer.invalidate()
                    self.countdown = nil
                    self.performLock()
                } else {
                    self.countdown = next
                    HUD.shared.show(symbol: "lock.fill",
                                    title: "Блокировка через \(next)",
                                    subtitle: "⎋ или \(self.unlockCombo.display) — отмена",
                                    tint: .systemOrange,
                                    duration: 1.1)
                }
            }
        }
        HUD.shared.show(symbol: "lock.fill",
                        title: "Блокировка через 3",
                        subtitle: "⎋ или \(unlockCombo.display) — отмена",
                        tint: .systemOrange,
                        duration: 1.1)
    }

    func abortCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = nil
        EventTap.shared.setMode(.idle)
        show(.init(kind: .info, text: "Блокировка отменена"))
        HUD.shared.show(symbol: "xmark.circle.fill",
                        title: "Отменено",
                        tint: .systemGray,
                        duration: 0.9)
    }

    private func performLock() {
        let tap = EventTap.shared

        // 1. The tap must be live *before* anything else is disabled.
        guard tap.isEnabled else {
            show(.init(kind: .error, text: "Перехват ввода не активен — блокировка не включена"))
            return
        }

        tap.blockKeyboard = blockKeyboard
        // The trackpad is blocked by swallowing pointer events at the HID level.
        // macOS does not expose per-device identity to event taps, so an external
        // mouse is swallowed as well — that is called out in the UI.
        tap.blockPointer = blockTrackpad
        tap.frozenCursorPosition = blockTrackpad ? CGEvent(source: nil)?.location : nil
        tap.blockTouchBar = blockTouchBar
        pointerFallbackActive = false

        // 2. Touch Bar (best effort, private DFR API).
        if blockTouchBar {
            if !TouchBarController.shared.block() {
                show(.init(kind: .warning, text: "Touch Bar недоступен на этом Mac — пропускаю"))
            }
        }

        tap.setMode(.blocking)
        isLocked = true
        restartAutoUnlockTimer()

        HUD.shared.show(symbol: "lock.fill",
                        title: "Заблокировано",
                        subtitle: "Разблокировка: \(unlockCombo.display)  ·  аварийно: ⎋ ×5",
                        tint: .systemRed,
                        duration: 2.4)
        show(.init(kind: .warning, text: "Заблокировано. Разблокировать: \(unlockCombo.display) или ⎋ пять раз подряд"))
    }

    enum UnlockReason: String {
        case combination, button, timer, wake, quit, screenUnlock, emergency
    }

    func performUnlock(reason: UnlockReason = .button) {
        countdownTimer?.invalidate(); countdownTimer = nil; countdown = nil
        autoUnlockTimer?.invalidate(); autoUnlockTimer = nil

        EventTap.shared.setMode(.idle)
        EventTap.shared.blockKeyboard = false
        EventTap.shared.blockPointer = false
        EventTap.shared.blockTouchBar = false
        EventTap.shared.frozenCursorPosition = nil
        TouchBarController.shared.unblock()
        pointerFallbackActive = false

        let wasLocked = isLocked
        isLocked = false

        guard wasLocked else { return }

        switch reason {
        case .combination:
            HUD.shared.show(symbol: "lock.open.fill", title: "Разблокировано",
                            subtitle: unlockCombo.display, tint: .systemGreen, duration: 1.6)
            show(.init(kind: .success, text: "Разблокировано комбинацией"))
        case .timer:
            HUD.shared.show(symbol: "lock.open.fill", title: "Разблокировано",
                            subtitle: "авторазблокировка", tint: .systemGreen, duration: 1.6)
        case .wake:
            HUD.shared.show(symbol: "lock.open.fill", title: "Разблокировано",
                            subtitle: "после пробуждения", tint: .systemGreen, duration: 1.6)
        default:
            HUD.shared.show(symbol: "lock.open.fill", title: "Разблокировано",
                            tint: .systemGreen, duration: 1.2)
        }
    }

    func toggleLock() {
        if isLocked { performUnlock(reason: .button) }
        else if countdown != nil { abortCountdown() }
        else { requestLock() }
    }

    // MARK: - Timers & notifications

    private func restartAutoUnlockTimer() {
        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil
        guard isLocked, autoUnlockMinutes > 0 else { return }
        autoUnlockTimer = Timer.scheduledTimer(withTimeInterval: Double(autoUnlockMinutes) * 60,
                                               repeats: false) { [weak self] _ in
            Task { @MainActor in self?.performUnlock(reason: .timer) }
        }
    }

    @objc private func didWake() {
        guard isLocked, unlockOnWake else { return }
        performUnlock(reason: .wake)
    }

    @objc private func screenUnlocked() {
        guard isLocked else { return }
        performUnlock(reason: .screenUnlock)
    }

    @objc private func appWillTerminate() {
        performUnlock(reason: .quit)
    }

    // MARK: - Notices

    func show(_ notice: Notice) {
        self.notice = notice
        let id = notice.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.notice?.id == id else { return }
            self.notice = nil
        }
    }

    /// Runtime summary used by the big button and the status row.
    var blockedTargetsSummary: String {
        var parts: [String] = []
        if blockKeyboard { parts.append("клавиатура") }
        if blockTrackpad { parts.append("трекпад") }
        if blockTouchBar { parts.append("Touch Bar") }
        return parts.isEmpty ? "ничего не выбрано" : parts.joined(separator: " · ")
    }

    // MARK: - Screenshot / demo support

    /// Used by `--demo --state verified` to render the "ready" look without a real
    /// global capture. Never reachable from the shipping UI.
    func forceVerifiedForDemo() {
        comboVerified = true
    }

    /// Visual-only lock for screenshots: no input is suppressed.
    func forceLockedForDemo() {
        isLocked = true
    }
}
