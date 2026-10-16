import Cocoa
import Carbon.HIToolbox
import CoreGraphics

/// `kCGEventSystemDefined` (a.k.a. `NX_SYSDEFINED`) has no Swift case name, but it is
/// the type the Touch Bar reports its taps with.
let kSystemDefinedEventType = CGEventType(rawValue: 14)!

/// What the event tap is currently doing.
enum TapMode {
    /// Tap is alive but every event passes straight through.
    case idle
    /// Waiting for the user to press the unlock combination so we can prove it works.
    case capture
    /// 3‑2‑1 countdown: nothing is blocked yet, Esc aborts.
    case arming
    /// Selected targets are blocked. The unlock combination and the emergency
    /// Escape×5 sequence stay live no matter what.
    case blocking
}

/// Owns the global `CGEventTap` that suppresses keyboard input and (as a fallback)
/// pointer input.
///
/// Safety rules baked into this class:
///  * the tap is only *ever* armed after the unlock combination has been proven;
///  * the unlock combination is evaluated **before** any suppression, on every event;
///  * Escape pressed 5× within 3 s always unlocks, independent of the settings;
///  * if macOS disables the tap too often (callback too slow), we unlock immediately
///    instead of leaving the user with a dead keyboard.
final class EventTap {

    static let shared = EventTap()

    private(set) var isInstalled = false
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Current mode. Written and read on the main thread only — the tap source is
    /// attached to the main run loop, so the callback is single threaded with the UI.
    private(set) var mode: TapMode = .idle

    /// Number of events suppressed since the last reset — used by `--selftest`.
    private(set) var suppressedEventCount = 0

    /// Cursor position to pin to while the pointer is blocked. `CGWarpMouseCursorPosition`
    /// does not generate events, so warping back inside the tap has no feedback loop.
    var frozenCursorPosition: CGPoint?

    private let pointerMovementTypes: Set<CGEventType> = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]

    // Policy, read inside the callback.
    var blockKeyboard = false
    var blockPointer = false          // trackpad / mouse: suppress pointer traffic
    var blockTouchBar = false         // Touch Bar taps arrive as `.systemDefined` events
    var unlockCombo: KeyCombo = .default

    // Callbacks
    var onUnlock: (() -> Void)?
    var onComboCaptured: (() -> Void)?
    var onAbort: (() -> Void)?

    // Emergency sequence bookkeeping
    private var escapeTimes: [CFTimeInterval] = []
    private let escapeWindow: CFTimeInterval = 3.0
    private let escapeCount = 5

    // Timeout bookkeeping
    private var timeoutReenableTimes: [CFTimeInterval] = []

    private let keyEventTypes: Set<CGEventType> = [.keyDown, .keyUp, .flagsChanged]
    private let pointerEventTypes: Set<CGEventType> = [
        .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .scrollWheel,
    ]

    private init() {}

    // MARK: - Installation

    /// Returns true when the tap is live. Requires Accessibility permission.
    @discardableResult
    func install() -> Bool {
        if isInstalled { return true }
        guard Permissions.isAccessibilityGranted else { return false }

        var mask: CGEventMask = 0
        for type in keyEventTypes.union(pointerEventTypes).union([kSystemDefinedEventType]) {
            mask |= CGEventMask(1) << CGEventMask(type.rawValue)
        }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // A HID-level tap sees events before the window server: that is the only
        // place where suppressing pointer traffic also stops the cursor itself.
        // Fall back to the session tap if the system refuses the HID tap.
        var port: CFMachPort?
        for candidate in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            port = CGEvent.tapCreate(tap: candidate,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest: mask,
                                     callback: callback,
                                     userInfo: refcon)
            if port != nil {
                location = candidate
                break
            }
        }
        guard let port else { return false }

        machPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isInstalled = true
        return true
    }

    /// True when the tap exists *and* the system currently has it enabled.
    var isEnabled: Bool {
        guard let port = machPort else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// Where the tap ended up being placed.
    private(set) var location: CGEventTapLocation = .cgSessionEventTap

    var isHIDLevel: Bool { location == .cghidEventTap }

    func uninstall() {
        if let port = machPort { CGEvent.tapEnable(tap: port, enable: false) }
        if let source = runLoopSource, let port = machPort {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(port)
        }
        runLoopSource = nil
        machPort = nil
        isInstalled = false
        mode = .idle
    }

    func setMode(_ newMode: TapMode) {
        mode = newMode
        if newMode != .blocking {
            escapeTimes.removeAll()
            frozenCursorPosition = nil
        }
        if newMode == .idle { timeoutReenableTimes.removeAll() }
    }

    // MARK: - Callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // The system disables a tap whose callback is too slow (or on user request).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableAfterTimeout()
            return pass
        }

        // The Touch Bar reports every tap as a system-defined event
        // (`kCGEventSystemDefined`), which is what makes it possible to block it.
        if type == kSystemDefinedEventType {
            if mode == .blocking, blockTouchBar {
                suppressedEventCount += 1
                return nil
            }
            return pass
        }

        let isKeyEvent = keyEventTypes.contains(type)
        guard isKeyEvent else {
            if mode == .blocking, blockPointer, pointerEventTypes.contains(type) {
                suppressedEventCount += 1
                // The window server has already applied the movement by the time a
                // tap sees it, so suppressing the event alone leaves the cursor
                // gliding. Pinning it back is what makes the trackpad feel dead.
                if pointerMovementTypes.contains(type), let frozen = frozenCursorPosition {
                    CGWarpMouseCursorPosition(frozen)
                }
                return nil
            }
            return pass
        }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let mods = KeyCombo.mods(from: event.flags)

        // ---- 1. Highest priority: the configured unlock combination -------------
        if mods == unlockCombo.mods, keyCode == unlockCombo.keyCode {
            switch mode {
            case .capture:
                mode = .idle
                onComboCaptured?()
                return nil
            case .arming:
                setMode(.idle)
                onAbort?()
                return nil
            case .blocking:
                setMode(.idle)
                onUnlock?()
                return nil
            case .idle:
                break                   // never swallow the combo while idle
            }
        }

        // ---- 2. Emergency Escape×5 while blocking ------------------------------
        // Auto-repeat is ignored so that holding Escape down is not enough —
        // it takes five deliberate presses.
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if mode == .blocking, type == .keyDown, !isAutoRepeat, keyCode == UInt16(kVK_Escape) {
            let now = CACurrentMediaTime()
            escapeTimes.append(now)
            escapeTimes.removeAll { now - $0 > escapeWindow }
            if escapeTimes.count >= escapeCount {
                escapeTimes.removeAll()
                setMode(.idle)
                onUnlock?()
                return nil
            }
        }

        // ---- 3. Escape aborts the arming countdown -----------------------------
        if mode == .arming, type == .keyDown, keyCode == UInt16(kVK_Escape) {
            setMode(.idle)
            onAbort?()
            return nil
        }

        // ---- 4. Suppression ----------------------------------------------------
        guard mode == .blocking else { return pass }
        if blockKeyboard {
            suppressedEventCount += 1
            return nil
        }
        return pass
    }

    private func reenableAfterTimeout() {
        guard let port = machPort else { return }
        CGEvent.tapEnable(tap: port, enable: true)

        // If the system keeps killing our tap we are one step away from a locked
        // Mac with a dead keyboard — bail out and unblock everything.
        let now = CACurrentMediaTime()
        timeoutReenableTimes.append(now)
        timeoutReenableTimes.removeAll { now - $0 > 10.0 }
        if timeoutReenableTimes.count > 5, mode == .blocking {
            timeoutReenableTimes.removeAll()
            setMode(.idle)
            onUnlock?()
        }
    }
}
